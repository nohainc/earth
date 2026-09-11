import type { PostgresRepository } from './repository.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { marketFeeRate } from './market-rules.ts';
import { getActiveMarketInstrument, getActiveSpotInstrument, MARKET_ASSET_IDS } from './market-model.ts';
import { MARKET_BATCH_GAME_MINUTES } from './market-model.ts';
import { calculateFeeUnits, calculateFeeUnitsBps, calculateQuoteUnits, displayPriceToUnits, displayQuantityToUnits, displayRateToBps, priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { marketBatchId } from './market-time.ts';
import { closeEscrowAccount, marketAccount, postSettlementBatch, releaseReservation, reserveForOrder } from './market-escrow.ts';
import { clearMarketAuction } from './market-clearing-engine.ts';
import { rebuildMarketInstrumentState, refreshMarketPriceProjection } from './market-state.ts';

type MarketOrderInput = {
  humanId: string;
  product: string;
  side: 'buy' | 'sell';
  quantity: number;
  limitPrice: number;
  correlationId: string;
  instrumentId?: string;
};

const assetIds: Record<string, number> = {
  food: MARKET_ASSET_IDS.FOOD,
  material: MARKET_ASSET_IDS.MATERIAL,
  components: MARKET_ASSET_IDS.COMPONENTS,
  energy: MARKET_ASSET_IDS.ENERGY,
  compute: MARKET_ASSET_IDS.COMPUTE,
};

export async function submitMarketOrder(repository: PostgresRepository, input: MarketOrderInput): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM market_orders WHERE owner_economic_id = (SELECT owner.economic_id FROM humans JOIN owner_registry owner ON owner.id = humans.house_id WHERE humans.id = $1) AND correlation_id = $2', [input.humanId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, order: prior.rows[0], correlationId: input.correlationId };
    const human = await tx.query('SELECT id FROM humans WHERE id = $1', [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const instrument = input.instrumentId
      ? await getActiveMarketInstrument(tx, input.instrumentId)
      : await getActiveSpotInstrument(tx, input.product);
    if (!instrument) throw new Error('Unknown or inactive market instrument');
    const buyerFeeRate = input.side === 'buy' ? await marketFeeRate(tx, input.humanId) : '0';
    const sellerFeeRate = input.side === 'sell' ? await marketFeeRate(tx, input.humanId) : '0';
    const quantityUnits = displayQuantityToUnits(input.quantity);
    const limitPriceUnits = displayPriceToUnits(input.limitPrice);
    const quoteUnits = calculateQuoteUnits(quantityUnits, limitPriceUnits);
    const reservedCents = input.side === 'buy' ? quoteUnits + calculateFeeUnits(quoteUnits, buyerFeeRate) : 0n;
    const reserved = input.side === 'buy' ? centsToMoney(reservedCents) : '0.00';
    const buyerFeeBps = input.side === 'buy' ? displayRateToBps(buyerFeeRate) : 0;
    const sellerFeeBps = input.side === 'sell' ? displayRateToBps(sellerFeeRate) : 0;
    const orderRulesSnapshot = JSON.stringify({
      rulesVersion: instrument.rules_version,
      buyerFeeBps,
      sellerFeeBps,
      lotSizeUnits: instrument.lot_size_units,
      priceTickUnits: instrument.price_tick_units,
    });
    const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const gameMinute = Number(world.rows[0]?.game_minute ?? 0);
    const eligibleBatchId = marketBatchId(gameDay, gameMinute, MARKET_BATCH_GAME_MINUTES) + 1;
    const orderId = crypto.randomUUID();
    const marketAssetId = instrument.base_asset_id;
    let v2Escrow: string;
    if (input.side === 'sell') {
      const inventoryAccount = await marketAccount(tx, input.humanId, marketAssetId);
      if (!inventoryAccount) throw new Error(`Market ${input.product} inventory account is missing`);
      v2Escrow = await reserveForOrder(tx, { ownerId: input.humanId, assetId: marketAssetId, sourceAccountId: inventoryAccount, amountUnits: quantityUnits, orderId, gameDay, reason: 'market_sell_escrow' });
    } else {
      const buyerAccount = await marketAccount(tx, input.humanId, 1);
      if (!buyerAccount) throw new Error('Market CREDIT account is missing');
      const buyerBalance = await tx.query<{ balance: string }>('SELECT balance::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [buyerAccount]);
      if (!buyerBalance.rows[0] || BigInt(buyerBalance.rows[0].balance) < reservedCents) throw new Error('Insufficient Credits to reserve this order');
      v2Escrow = await reserveForOrder(tx, { ownerId: input.humanId, assetId: 1, sourceAccountId: buyerAccount, amountUnits: reservedCents, orderId, gameDay, reason: 'market_order_reservation' });
    }
    await tx.query('INSERT INTO market_orders (id, human_id, product, side, quantity, limit_price, quantity_units, limit_price_units, filled_quantity_units, reserved_quote_units, owner_economic_id, instrument_id, filled_units, eligible_batch_id, escrow_account_id, reserved_base_units, buyer_fee_bps, seller_fee_bps, rules_version, rules_snapshot, submitted_game_day, submitted_game_minute, correlation_id) SELECT $1,$2,$3,$4,$5,$6,$7,$8,0,$9,o.economic_id,$10,0,$11,$12,$13,$14,$15,$16,$17::JSONB,$18,$19,$20 FROM owner_registry o WHERE o.id = COALESCE((SELECT house_id FROM humans WHERE id = $2), $2)', [orderId, input.humanId, input.product, input.side, unitsToDisplayQuantity(quantityUnits), priceUnitsToDisplayPrice(limitPriceUnits), quantityUnits.toString(), limitPriceUnits.toString(), reservedCents.toString(), instrument.id, eligibleBatchId, v2Escrow, input.side === 'sell' ? quantityUnits.toString() : '0', buyerFeeBps, sellerFeeBps, instrument.rules_version, orderRulesSnapshot, gameDay, gameMinute, input.correlationId]);
    const state = await rebuildMarketInstrumentState(tx, instrument.id);
    await refreshMarketPriceProjection(tx, instrument, state, gameDay);
    const order = await tx.query('SELECT * FROM market_orders WHERE id = $1', [orderId]);
    return { ok: true, order: order.rows[0], correlationId: input.correlationId };
  });
}

/** Clear and post every fill for one instrument batch in a single transaction. */
export async function settleMarketBatch(repository: PostgresRepository, product: string, batchId: number, settlementGameDay?: number, instrumentId?: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const instrument = instrumentId
      ? await getActiveMarketInstrument(tx, instrumentId)
      : await getActiveSpotInstrument(tx, product);
    if (!instrument) throw new Error('Unknown or inactive market instrument');
    const state = await rebuildMarketInstrumentState(tx, instrument.id);
    const game = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
    const orders = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE instrument_id = $1 AND status IN ('open','partial') AND eligible_batch_id <= $2 AND ((side = 'buy' AND reserved_quote_units > 0) OR (side = 'sell' AND reserved_base_units > 0)) ORDER BY side, limit_price_units, sequence_no FOR UPDATE", [instrument.id, batchId]);
    const buyRows = orders.rows.filter((row) => row.side === 'buy');
    const sellRows = orders.rows.filter((row) => row.side === 'sell');
    const auction = clearMarketAuction({
      previousClearingPriceUnits: BigInt(state.last_clearing_price_units ?? 0),
      buyOrders: buyRows.map((row) => ({ id: String(row.id), ownerId: String(row.owner_economic_id), side: 'BUY' as const, quantityUnits: BigInt(String(row.quantity_units)), filledUnits: BigInt(String(row.filled_quantity_units)), limitPriceUnits: BigInt(String(row.limit_price_units)), sequenceNo: BigInt(String(row.sequence_no)) })),
      sellOrders: sellRows.map((row) => ({ id: String(row.id), ownerId: String(row.owner_economic_id), side: 'SELL' as const, quantityUnits: BigInt(String(row.quantity_units)), filledUnits: BigInt(String(row.filled_quantity_units)), limitPriceUnits: BigInt(String(row.limit_price_units)), sequenceNo: BigInt(String(row.sequence_no)) })),
    });
    if (!auction.fills.length) return { ok: true, filled: false, fillCount: 0, selfTradePreventedUnits: auction.statistics.selfTradePreventedUnits.toString() };
    const day = settlementGameDay ?? Number(game.rows[0]?.game_day ?? 0);
    const effects = new Map<string, { accountId: string; assetId: number; delta: bigint; reason: string }>();
    const addEffect = (accountId: string, assetId: number, delta: bigint, reason: string) => {
      const key = `${accountId}:${assetId}`;
      const existing = effects.get(key);
      if (existing) existing.delta += delta;
      else effects.set(key, { accountId, assetId, delta, reason });
    };
    const orderUpdates = new Map<string, { filled: bigint; quote: bigint; base: bigint; status: string }>();
    const fillRows: Array<Record<string, string>> = [];
    const closeAccounts = new Set<string>();
    const ouc = (await tx.query<{ economic_account_id: string }>('SELECT economic_account_id::TEXT FROM economic_account_migrations WHERE legacy_account_id = $1', ['account-ouc-treasury'])).rows[0]?.economic_account_id;
    for (const fill of auction.fills) {
      const buy = buyRows.find((row) => String(row.id) === fill.buyOrderId)!;
      const sell = sellRows.find((row) => String(row.id) === fill.sellOrderId)!;
      const total = calculateQuoteUnits(fill.quantityUnits, fill.priceUnits);
      const fee = calculateFeeUnitsBps(total, String(buy.buyer_fee_bps ?? 0));
      const limitQuote = calculateQuoteUnits(fill.quantityUnits, BigInt(String(buy.limit_price_units)));
      const used = limitQuote + calculateFeeUnitsBps(limitQuote, String(buy.buyer_fee_bps ?? 0));
      const refund = used - (total + fee);
      const buyEscrow = String(buy.escrow_account_id); const sellEscrow = String(sell.escrow_account_id);
      const sellerAccount = await marketAccount(tx, String(sell.human_id), 1);
      const buyerAccount = await marketAccount(tx, String(buy.human_id), 1);
      const buyerInventory = await marketAccount(tx, String(buy.human_id), instrument.base_asset_id);
      if (!sellerAccount || !buyerAccount || !buyerInventory || !ouc || !buy.escrow_account_id || !sell.escrow_account_id) throw new Error('Market batch settlement accounts are missing');
      addEffect(buyEscrow, 1, -used, 'market_batch_trade');
      addEffect(sellerAccount, 1, total, 'market_batch_trade');
      if (fee > 0n) addEffect(ouc, 1, fee, 'market_batch_fee');
      if (refund > 0n) addEffect(buyerAccount, 1, refund, 'market_batch_refund');
      addEffect(sellEscrow, instrument.base_asset_id, -fill.quantityUnits, 'market_batch_trade');
      addEffect(buyerInventory, instrument.base_asset_id, fill.quantityUnits, 'market_batch_trade');
      const buyUpdate = orderUpdates.get(String(buy.id)) ?? { filled: BigInt(String(buy.filled_quantity_units)), quote: BigInt(String(buy.reserved_quote_units)), base: 0n, status: 'partial' };
      buyUpdate.filled += fill.quantityUnits; buyUpdate.quote = buyUpdate.quote >= used ? buyUpdate.quote - used : 0n;
      if (buyUpdate.filled >= BigInt(String(buy.quantity_units))) { buyUpdate.status = 'filled'; closeAccounts.add(buyEscrow); }
      orderUpdates.set(String(buy.id), buyUpdate);
      const sellUpdate = orderUpdates.get(String(sell.id)) ?? { filled: BigInt(String(sell.filled_quantity_units)), quote: 0n, base: BigInt(String(sell.reserved_base_units)), status: 'partial' };
      sellUpdate.filled += fill.quantityUnits; sellUpdate.base = sellUpdate.base >= fill.quantityUnits ? sellUpdate.base - fill.quantityUnits : 0n;
      if (sellUpdate.filled >= BigInt(String(sell.quantity_units))) { sellUpdate.status = 'filled'; closeAccounts.add(sellEscrow); }
      orderUpdates.set(String(sell.id), sellUpdate);
      fillRows.push({ id: crypto.randomUUID(), batch_id: String(batchId), instrument_id: instrument.id, buy_order_id: String(buy.id), sell_order_id: String(sell.id), buyer_economic_id: String(buy.owner_economic_id), seller_economic_id: String(sell.owner_economic_id), quantity_units: fill.quantityUnits.toString(), price_units: fill.priceUnits.toString(), quote_units: total.toString(), gross_quote_units: total.toString(), fee_units: fee.toString(), buyer_fee_units: fee.toString(), seller_fee_units: '0', sequence_no: String(fillRows.length + 1), game_day: String(day), game_minute: String(game.rows[0]?.game_minute ?? 0) });
    }
    const entries = [...effects.values()].filter((entry) => entry.delta !== 0n);
    const posted = await postSettlementBatch(tx, day, `market-batch:${batchId}:${instrument.id}`, `${batchId}:${instrument.id}`, entries);
    if (!posted.created) return { ok: true, filled: false, alreadyProcessed: true, fillCount: fillRows.length };
    const updateRows = [...orderUpdates.entries()].map(([orderId, update]) => ({ order_id: orderId, filled: update.filled.toString(), quote: update.quote.toString(), base: update.base.toString(), status: update.status }));
    await tx.query(`WITH updates AS (SELECT * FROM jsonb_to_recordset($1::jsonb) AS x(order_id UUID, filled BIGINT, quote BIGINT, base BIGINT, status TEXT))
      UPDATE market_orders o SET filled_quantity_units = u.filled, filled_units = u.filled, reserved_quote_units = u.quote, reserved_base_units = u.base, filled_quantity = u.filled / 1000000.0, status = u.status WHERE o.id = u.order_id`, [JSON.stringify(updateRows)]);
    const persistedFillRows = fillRows.map((row) => ({ ...row, economic_transaction_id: posted.transactionId }));
    await tx.query(`INSERT INTO market_fills (id, batch_id, instrument_id, buy_order_id, sell_order_id, buyer_economic_id, seller_economic_id, quantity_units, price_units, quote_units, gross_quote_units, fee_units, buyer_fee_units, seller_fee_units, economic_transaction_id, sequence_no, game_day, game_minute)
      SELECT id, batch_id, instrument_id, buy_order_id, sell_order_id, buyer_economic_id, seller_economic_id, quantity_units, price_units, quote_units, gross_quote_units, fee_units, buyer_fee_units, seller_fee_units, economic_transaction_id, sequence_no, game_day, game_minute FROM jsonb_to_recordset($1::jsonb) AS x(id UUID, batch_id BIGINT, instrument_id TEXT, buy_order_id UUID, sell_order_id UUID, buyer_economic_id BIGINT, seller_economic_id BIGINT, quantity_units BIGINT, price_units BIGINT, quote_units BIGINT, gross_quote_units BIGINT, fee_units BIGINT, buyer_fee_units BIGINT, seller_fee_units BIGINT, economic_transaction_id BIGINT, sequence_no BIGINT, game_day BIGINT, game_minute INTEGER) ON CONFLICT DO NOTHING`, [JSON.stringify(persistedFillRows)]);
    const volume = auction.fills.reduce((sum, fill) => sum + fill.quantityUnits, 0n);
    for (const accountId of closeAccounts) await closeEscrowAccount(tx, accountId, `${batchId}:${instrument.id}`);
    const rebuiltState = await rebuildMarketInstrumentState(tx, instrument.id);
    await refreshMarketPriceProjection(tx, instrument, rebuiltState, day);
    return { ok: true, filled: true, fillCount: fillRows.length, quantityUnits: volume.toString(), clearingPriceUnits: auction.clearingPriceUnits?.toString() ?? null, economicTransactionId: posted.transactionId, selfTradePreventedUnits: auction.statistics.selfTradePreventedUnits.toString() };
  });
}

export async function listMarketOrders(repository: PostgresRepository, product: string | null): Promise<Record<string, unknown>> {
  const result = product
    ? await repository.query('SELECT * FROM market_orders WHERE product = $1 ORDER BY created_at DESC LIMIT 100', [product])
    : await repository.query('SELECT * FROM market_orders ORDER BY created_at DESC LIMIT 100');
  return { orders: result.rows };
}

export async function cancelMarketOrder(repository: PostgresRepository, input: { orderId: string; humanId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
      const order = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE id = $1 AND owner_economic_id = (SELECT owner.economic_id FROM humans JOIN owner_registry owner ON owner.id = humans.house_id WHERE humans.id = $2) AND status IN ('open','partial') FOR UPDATE", [input.orderId, input.humanId]);
    if (!order.rows[0]) throw new Error('Open order not found for this Human');
    const current = order.rows[0];
    const remainingUnits = BigInt(String(current.quantity_units)) - BigInt(String(current.filled_quantity_units));
    const remaining = Number(unitsToDisplayQuantity(remainingUnits));
    const day = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
    const instrument = await getActiveMarketInstrument(tx, String(current.instrument_id));
    if (String(current.side) === 'sell') {
      const inventory = await marketAccount(tx, input.humanId, assetIds[String(current.product)]);
      if (!inventory || !current.escrow_account_id) throw new Error('Market V2 sell escrow is missing');
      await releaseReservation(tx, { escrowAccountId: String(current.escrow_account_id), destinationAccountId: inventory, assetId: assetIds[String(current.product)], amountUnits: remainingUnits, orderId: input.orderId, gameDay: day, reason: 'market_order_cancel_refund' });
      await closeEscrowAccount(tx, String(current.escrow_account_id), input.orderId);
    } else {
      const v2Buyer = await marketAccount(tx, input.humanId, 1);
      if (!v2Buyer || !current.escrow_account_id) throw new Error('Market V2 buy escrow is missing');
      const refundUnits = BigInt(String(current.reserved_quote_units));
      if (refundUnits > 0n) await releaseReservation(tx, { escrowAccountId: String(current.escrow_account_id), destinationAccountId: v2Buyer, assetId: 1, amountUnits: refundUnits, orderId: input.orderId, gameDay: day, reason: 'market_order_cancellation' });
      await closeEscrowAccount(tx, String(current.escrow_account_id), input.orderId);
    }
    await tx.query("UPDATE market_orders SET status = 'cancelled', reserved_quote_units = 0, reserved_base_units = 0 WHERE id = $1 AND owner_economic_id = (SELECT owner.economic_id FROM humans JOIN owner_registry owner ON owner.id = humans.house_id WHERE humans.id = $2)", [input.orderId, input.humanId]);
    const spotInstrument = await getActiveSpotInstrument(tx, String(current.product));
    if (spotInstrument) {
      const state = await rebuildMarketInstrumentState(tx, spotInstrument.id);
      await refreshMarketPriceProjection(tx, spotInstrument, state, day);
    }
    return { ok: true, orderId: input.orderId, released: remaining, side: current.side };
  });
}
