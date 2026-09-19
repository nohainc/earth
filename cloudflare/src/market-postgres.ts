import type { PostgresRepository } from './repository.ts';
import { marketFeeRate } from './market-rules.ts';
import { getActiveMarketInstrument, getActiveSpotInstrument, MARKET_ASSET_IDS } from './market-model.ts';
import { MARKET_BATCH_GAME_MINUTES } from './market-model.ts';
import { calculateFeeUnits, calculateFeeUnitsBps, calculateQuoteUnits, displayPriceToUnits, displayQuantityToUnits, displayRateToBps, priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { gamePosition, marketBatchId, marketBatchRange } from './market-time.ts';
import { getMarketReservation, marketAccount, marketEconomicAccount, postSettlementBatch, releaseReservation, reserveForOrder, updateReservationRemaining } from './market-escrow.ts';
import { clearMarketAuction } from './market-clearing-engine.ts';
import { rebuildMarketInstrumentState, refreshMarketPriceProjection } from './market-state.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { END_OF_GAME_DAY_MINUTE } from './economic-transaction-postgres.ts';

type MarketOrderInput = {
  humanId: string;
  product: string;
  side: 'buy' | 'sell';
  quantity: number | string;
  limitPrice: number | string;
  correlationId: string;
  instrumentId?: string;
  ownerId?: string;
  corporationId?: string;
  ownerEconomicId?: string;
  sourceType?: 'MANUAL' | 'HOUSE_POLICY' | 'CORPORATION_POLICY' | 'CORPORATION';
  policyId?: string;
  policyBudgetId?: string;
  goodTilGameDay?: number;
};

const assetIds: Record<string, number> = {
  food: MARKET_ASSET_IDS.FOOD,
  material: MARKET_ASSET_IDS.MATERIAL,
  components: MARKET_ASSET_IDS.COMPONENTS,
  energy: MARKET_ASSET_IDS.ENERGY,
  compute: MARKET_ASSET_IDS.COMPUTE,
};

async function ensureMarketBatch(tx: PostgresRepository, gameDay: number, gameMinute: number): Promise<number> {
  const correlationId = `market-batch:${marketBatchId(gameDay, gameMinute, MARKET_BATCH_GAME_MINUTES)}`;
  const result = await tx.query<{ id: string }>(
    `INSERT INTO market_batches (game_day, game_minute, status, correlation_id)
     VALUES ($1, $2, 'OPEN', $3) ON CONFLICT (correlation_id) DO UPDATE SET correlation_id = EXCLUDED.correlation_id RETURNING id`,
    [gameDay, gameMinute, correlationId],
  );
  return Number(result.rows[0].id);
}

async function earthTreasury(tx: PostgresRepository): Promise<string | null> {
  const result = await tx.query<{ account_id: string }>(
    `SELECT a.id::TEXT AS account_id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      WHERE o.owner_type = 'EARTH' AND a.asset_id = 1 AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE' LIMIT 1`,
  );
  return result.rows[0]?.account_id ?? null;
}

import { runEconomicMutation } from './settlement-barrier-postgres.ts';

export async function submitMarketOrder(repository: PostgresRepository, input: MarketOrderInput): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const prior = await tx.query('SELECT * FROM market_orders WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, order: prior.rows[0], correlationId: input.correlationId };
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND status = 'ACTIVE'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found or inactive');
    const instrument = input.instrumentId ? await getActiveMarketInstrument(tx, input.instrumentId) : await getActiveSpotInstrument(tx, input.product);
    if (!instrument) throw new Error('Unknown or inactive market instrument');
    const quantityUnits = displayQuantityToUnits(input.quantity);
    const limitPriceUnits = displayPriceToUnits(input.limitPrice);
    const buyerFeeRate = input.side === 'buy' ? await marketFeeRate(tx, input.humanId) : '0';
    const reservedCents = input.side === 'buy' ? calculateQuoteUnits(quantityUnits, limitPriceUnits) + calculateFeeUnits(calculateQuoteUnits(quantityUnits, limitPriceUnits), buyerFeeRate) : 0n;
    const buyerFeeBps = input.side === 'buy' ? displayRateToBps(buyerFeeRate) : 0;
    const batchId = await ensureMarketBatch(tx, clock.gameDay, clock.gameMinute);
    
    let ownerEconomicId: string;
    let ownerRegistryId: string;
    let ownerType: string;

    const requestedOwnerId = input.ownerId || input.corporationId || input.ownerEconomicId;
    if (requestedOwnerId) {
      const ownerRes = await tx.query<{ id: string; economic_id: string; owner_type: string }>(
        `SELECT o.id::TEXT, o.economic_id::TEXT, o.owner_type::TEXT
           FROM owner_registry o
          WHERE (o.id = $1 OR o.economic_id = $1)
            AND o.owner_type IN ('HOUSE', 'CORPORATION')
          LIMIT 1`,
        [requestedOwnerId],
      );
      if (!ownerRes.rows[0]) throw new Error('Requested market owner is not provisioned');
      const row = ownerRes.rows[0];
      if (row.owner_type === 'CORPORATION') {
        const authorized = await tx.query(
          `SELECT 1 FROM institution_governance_roles
            WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
              AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')
            UNION
            SELECT 1 FROM house_affiliations ha
            JOIN humans h ON h.house_id = ha.house_id
            WHERE ha.corporation_id = $1 AND h.id = $2 AND ha.status = 'ACTIVE'`,
          [row.id, input.humanId],
        );
        if (!authorized.rows[0]) throw new Error('Corporation market order authorization required');
      } else if (row.owner_type === 'HOUSE') {
        const authorized = await tx.query(
          `SELECT 1 FROM humans WHERE id = $1 AND house_id = $2 AND status = 'ACTIVE'`,
          [input.humanId, row.id],
        );
        if (!authorized.rows[0]) throw new Error('House market order authorization required');
      }
      ownerEconomicId = row.economic_id;
      ownerRegistryId = row.id;
      ownerType = row.owner_type;
    } else {
      const ownerRes = await tx.query<{ id: string; economic_id: string }>(
        "SELECT o.id::TEXT, o.economic_id::TEXT FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE' WHERE h.id = $1",
        [input.humanId],
      );
      if (!ownerRes.rows[0]) throw new Error('House economic owner is not provisioned');
      ownerEconomicId = ownerRes.rows[0].economic_id;
      ownerRegistryId = ownerRes.rows[0].id;
      ownerType = 'HOUSE';
    }

    const assetIdToReserve = input.side === 'buy' ? MARKET_ASSET_IDS.CREDIT : instrument.base_asset_id;
    const sourceAccount = await marketEconomicAccount(tx, ownerEconomicId, assetIdToReserve);
    if (!sourceAccount) throw new Error(`${ownerType === 'CORPORATION' ? 'Corporation' : 'House'} market source account is missing`);
    if (input.side === 'buy') {
      const balance = await tx.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [sourceAccount]);
      if (!balance.rows[0] || BigInt(balance.rows[0].balance_units) < reservedCents) throw new Error('Insufficient Credits to reserve this order');
    } else {
      const balance = await tx.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [sourceAccount]);
      if (!balance.rows[0] || BigInt(balance.rows[0].balance_units) < quantityUnits) throw new Error('Insufficient resource balance to reserve this order');
    }
    const orderId = crypto.randomUUID();
    await tx.query(
      `INSERT INTO market_orders (id, batch_id, instrument_id, owner_economic_id, side, quantity_units, remaining_units, limit_price_units, buyer_fee_bps, status, rules_version, correlation_id, source_type, policy_id, policy_budget_id, good_til_game_day)
       VALUES ($1, $2, $3, $4, $5, $6, $6, $7, $8, 'OPEN', $9, $10, $11, $12, $13, $14)`,
      [orderId, batchId, instrument.id, ownerEconomicId, input.side.toUpperCase(), quantityUnits.toString(), limitPriceUnits.toString(), buyerFeeBps, instrument.rules_version, input.correlationId, input.sourceType ?? 'MANUAL', input.policyId ?? null, input.policyBudgetId ?? null, input.goodTilGameDay ?? null],
    );
    await reserveForOrder(tx, { ownerId: ownerRegistryId, assetId: assetIdToReserve, sourceAccountId: sourceAccount, amountUnits: input.side === 'buy' ? reservedCents : quantityUnits, orderId, reason: input.side === 'buy' ? 'market_order_reservation' : 'market_sell_escrow' }, clock);
    await refreshMarketPriceProjection(tx, instrument, await rebuildMarketInstrumentState(tx, instrument.id), clock.gameDay);
    const order = await tx.query('SELECT * FROM market_orders WHERE id = $1', [orderId]);
    return { ok: true, order: order.rows[0], correlationId: input.correlationId };
  });
}

export async function settleMarketBatch(repository: PostgresRepository, product: string, batchRowId: number, instrumentId?: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const instrument = instrumentId ? await getActiveMarketInstrument(tx, instrumentId) : await getActiveSpotInstrument(tx, product);
    if (!instrument) throw new Error('Unknown or inactive market instrument');
    const currentBatch = (await tx.query<{ game_day: number; game_minute: number }>(
      'SELECT game_day, game_minute FROM market_batches WHERE id = $1',
      [batchRowId],
    )).rows[0];
    if (!currentBatch) throw new Error(`Market batch row ${batchRowId} does not exist`);
    // node-postgres returns BIGINT/INTEGER values as strings by default. Normalize
    // the persisted coordinates before passing them to the strict time helpers.
    // market_batches.id is only a database row identity; the absolute batch
    // range must always come from the persisted game coordinates.
    const batchGameDay = Number(currentBatch.game_day);
    const batchGameMinute = Number(currentBatch.game_minute);
    if (!Number.isInteger(batchGameDay) || batchGameDay < 1 || !Number.isInteger(batchGameMinute) || batchGameMinute < 0 || batchGameMinute >= 1_440) {
      throw new Error(`Market batch row ${batchRowId} has invalid game coordinates`);
    }
    const absoluteBatchNumber = marketBatchId(
      batchGameDay,
      batchGameMinute,
      MARKET_BATCH_GAME_MINUTES,
    );
    const orders = await tx.query<Record<string, unknown>>(
      `SELECT o.*
         FROM market_orders o
         JOIN market_batches origin ON origin.id = o.batch_id
        WHERE o.instrument_id = $1
          AND o.status IN ('OPEN','PARTIAL')
          AND o.remaining_units > 0
          AND (origin.game_day < $2 OR (origin.game_day = $2 AND origin.game_minute <= $3))
        ORDER BY o.created_at, o.id
        FOR UPDATE OF o`,
      [instrument.id, batchGameDay, batchGameMinute],
    );
    const buys = orders.rows.filter((row) => row.side === 'BUY');
    const sells = orders.rows.filter((row) => row.side === 'SELL');
    const auction = clearMarketAuction({
      previousClearingPriceUnits: 0n,
      buyOrders: buys.map((row, sequenceNo) => ({ id: String(row.id), ownerId: String(row.owner_economic_id), side: 'BUY' as const, quantityUnits: BigInt(String(row.quantity_units)), filledUnits: BigInt(String(row.quantity_units)) - BigInt(String(row.remaining_units)), limitPriceUnits: BigInt(String(row.limit_price_units)), sequenceNo: BigInt(sequenceNo) })),
      sellOrders: sells.map((row, sequenceNo) => ({ id: String(row.id), ownerId: String(row.owner_economic_id), side: 'SELL' as const, quantityUnits: BigInt(String(row.quantity_units)), filledUnits: BigInt(String(row.quantity_units)) - BigInt(String(row.remaining_units)), limitPriceUnits: BigInt(String(row.limit_price_units)), sequenceNo: BigInt(sequenceNo) })),
    });
    if (!auction.fills.length) return { ok: true, filled: false, fillCount: 0 };
    const batchRange = marketBatchRange(absoluteBatchNumber, MARKET_BATCH_GAME_MINUTES);
    const batchClosedAt = gamePosition(batchRange.endMinute - 1);
    const day = batchClosedAt.gameDay;
    const effects = new Map<string, EscrowEffect>();
    const add = (accountId: string, assetId: number, delta: bigint, reason: string) => {
      const key = `${accountId}:${assetId}`;
      const prior = effects.get(key);
      if (prior) prior.delta += delta;
      else effects.set(key, { accountId, assetId, delta, reason });
    };
    const updates = new Map<string, bigint>();
    const reservationMoves = new Map<string, { orderId: string; assetId: number; amount: bigint; finalStatus?: 'CONSUMED' | 'RELEASED' }>();
    const addReservationMove = (orderId: string, assetId: number, amount: bigint) => {
      const key = `${orderId}:${assetId}`;
      const prior = reservationMoves.get(key);
      if (prior) prior.amount += amount;
      else reservationMoves.set(key, { orderId, assetId, amount });
    };
    const earth = await earthTreasury(tx);
    if (!earth) throw new Error('EARTH treasury is not provisioned');
    for (const fill of auction.fills) {
      const buy = buys.find((row) => String(row.id) === fill.buyOrderId)!;
      const sell = sells.find((row) => String(row.id) === fill.sellOrderId)!;
      const quote = calculateQuoteUnits(fill.quantityUnits, fill.priceUnits);
      const buyerFee = calculateFeeUnitsBps(quote, String(buy.buyer_fee_bps ?? 0));
      const buyerReservation = await getMarketReservation(tx, String(buy.id), MARKET_ASSET_IDS.CREDIT);
      const sellerReservation = await getMarketReservation(tx, String(sell.id), instrument.base_asset_id);
      const sellerWallet = await marketEconomicAccount(tx, String(sell.owner_economic_id), MARKET_ASSET_IDS.CREDIT);
      const buyerInventory = await marketEconomicAccount(tx, String(buy.owner_economic_id), instrument.base_asset_id);
      if (!buyerReservation || !sellerReservation || !sellerWallet || !buyerInventory) throw new Error('Market reservation or destination account is missing');
      const used = quote + buyerFee;
      add(buyerReservation.escrow_account_id, MARKET_ASSET_IDS.CREDIT, -used, 'market_batch_trade');
      add(sellerWallet, MARKET_ASSET_IDS.CREDIT, quote, 'market_batch_trade');
      add(earth, MARKET_ASSET_IDS.CREDIT, buyerFee, 'market_batch_fee');
      add(sellerReservation.escrow_account_id, instrument.base_asset_id, -fill.quantityUnits, 'market_batch_trade');
      add(buyerInventory, instrument.base_asset_id, fill.quantityUnits, 'market_batch_trade');
      updates.set(String(buy.id), (updates.get(String(buy.id)) ?? 0n) + fill.quantityUnits);
      updates.set(String(sell.id), (updates.get(String(sell.id)) ?? 0n) + fill.quantityUnits);
      addReservationMove(String(buy.id), MARKET_ASSET_IDS.CREDIT, used);
      addReservationMove(String(sell.id), instrument.base_asset_id, fill.quantityUnits);
    }
    for (const [orderId, filled] of updates) {
      const order = orders.rows.find((row) => String(row.id) === orderId)!;
      const remainingAfterFill = BigInt(String(order.remaining_units)) - filled;
      if (remainingAfterFill !== 0n || order.side !== 'BUY') continue;
      const move = reservationMoves.get(`${orderId}:${MARKET_ASSET_IDS.CREDIT}`)!;
      const reservation = await getMarketReservation(tx, orderId, MARKET_ASSET_IDS.CREDIT);
      const buyerWallet = await marketEconomicAccount(tx, String(order.owner_economic_id), MARKET_ASSET_IDS.CREDIT);
      if (!reservation || !buyerWallet) throw new Error('Buyer reservation or wallet is missing');
      const refund = BigInt(String(reservation.remaining_units)) - move.amount;
      if (refund > 0n) {
        add(reservation.escrow_account_id, MARKET_ASSET_IDS.CREDIT, refund, 'market_order_reservation_release');
        add(buyerWallet, MARKET_ASSET_IDS.CREDIT, refund, 'market_order_reservation_release');
        move.amount += refund;
      }
      move.finalStatus = 'RELEASED';
    }
    const posted = await postSettlementBatch(tx, batchClosedAt.gameDay, batchClosedAt.gameMinute, `market-batch:${batchRowId}:${instrument.id}`, `${batchRowId}:${instrument.id}`, [...effects.values()].filter((entry) => entry.delta !== 0n));
    if (!posted.created) return { ok: true, filled: false, alreadyProcessed: true, fillCount: auction.fills.length };
    for (const move of reservationMoves.values()) await updateReservationRemaining(tx, move.orderId, move.assetId, move.amount, move.finalStatus);
    for (const [orderId, filled] of updates) await tx.query(`UPDATE market_orders SET remaining_units = remaining_units - $1, status = CASE WHEN remaining_units - $1 = 0 THEN 'FILLED' ELSE 'PARTIAL' END WHERE id = $2`, [filled.toString(), orderId]);
    for (const [sequenceNo, fill] of auction.fills.entries()) {
      const buy = buys.find((row) => String(row.id) === fill.buyOrderId)!;
      const sell = sells.find((row) => String(row.id) === fill.sellOrderId)!;
      await tx.query(
        `INSERT INTO market_fills (batch_id, instrument_id, buy_order_id, sell_order_id, buyer_economic_id, seller_economic_id, quantity_units, price_units, gross_quote_units, buyer_fee_units, seller_fee_units, economic_transaction_id, sequence_no)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,0,$11,$12) ON CONFLICT (batch_id, instrument_id, sequence_no) DO NOTHING`,
        [batchRowId, instrument.id, buy.id, sell.id, buy.owner_economic_id, sell.owner_economic_id, fill.quantityUnits.toString(), fill.priceUnits.toString(), calculateQuoteUnits(fill.quantityUnits, fill.priceUnits).toString(), '0', posted.transactionId, sequenceNo + 1],
      );
      await createGameEvent(tx, { id: `MARKET-TRADE-${batchRowId}-${instrument.id}-${sequenceNo + 1}`, category: 'MARKET', eventType: 'MARKET_TRADE', gameDay: day, subjectType: 'MARKET_INSTRUMENT', subjectId: instrument.id, title: `${instrument.symbol} market trade cleared`, details: { batchId: batchRowId, instrumentId: instrument.id, buyOrderId: buy.id, sellOrderId: sell.id, quantityUnits: fill.quantityUnits.toString(), priceUnits: fill.priceUnits.toString(), economicTransactionId: posted.transactionId }, correlationId: `market-trade:${batchRowId}:${instrument.id}:${sequenceNo + 1}` });
    }
    return { ok: true, filled: true, fillCount: auction.fills.length, quantityUnits: auction.fills.reduce((sum, fill) => sum + fill.quantityUnits, 0n).toString(), economicTransactionId: posted.transactionId };
  });
}

type EscrowEffect = { accountId: string; assetId: number; delta: bigint; reason: string };

export async function listMarketOrders(repository: PostgresRepository, product: string | null): Promise<Record<string, unknown>> {
  const result = product
    ? await repository.query(`SELECT o.* FROM market_orders o JOIN market_instruments i ON i.id = o.instrument_id WHERE i.symbol = $1 ORDER BY o.created_at DESC LIMIT 100`, [`SPOT-${product.trim().toUpperCase()}`])
    : await repository.query('SELECT * FROM market_orders ORDER BY created_at DESC LIMIT 100');
  return { orders: result.rows };
}

export async function cancelMarketOrder(repository: PostgresRepository, input: { orderId: string; humanId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const order = await tx.query<Record<string, unknown>>(
      `SELECT o.*, reg.id AS owner_id, reg.owner_type
         FROM market_orders o
         JOIN owner_registry reg ON reg.economic_id = o.owner_economic_id
        WHERE o.id = $1 AND o.status IN ('OPEN','PARTIAL')
        FOR UPDATE`,
      [input.orderId],
    );
    if (!order.rows[0]) throw new Error('Open order not found for this Human');
    const current = order.rows[0];
    const isHouseAuthorized = await tx.query(
      `SELECT 1 FROM humans WHERE id = $1 AND house_id = $2 AND status = 'ACTIVE'`,
      [input.humanId, current.owner_id],
    );
    const isCorpAuthorized = await tx.query(
      `SELECT 1 FROM institution_governance_roles
        WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
          AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')
        UNION
        SELECT 1 FROM house_affiliations ha
        JOIN humans h ON h.house_id = ha.house_id
        WHERE ha.corporation_id = $1 AND h.id = $2 AND ha.status = 'ACTIVE'`,
      [current.owner_id, input.humanId],
    );
    if (!isHouseAuthorized.rows[0] && !isCorpAuthorized.rows[0]) {
      throw new Error('Open order not found for this Human');
    }
    const reservation = await getMarketReservation(tx, input.orderId);
    const instrument = await getActiveMarketInstrument(tx, String(current.instrument_id));
    if (!reservation || !instrument) throw new Error('Market reservation is missing');
    const destination = await marketEconomicAccount(tx, String(current.owner_economic_id), reservation.asset_id);
    if (!destination) throw new Error('Refund account is missing');
    await releaseReservation(tx, {
      escrowAccountId: reservation.escrow_account_id,
      destinationAccountId: destination,
      assetId: reservation.asset_id,
      amountUnits: BigInt(reservation.remaining_units),
      orderId: input.orderId,
      context: clock,
      reason: 'market_order_cancellation',
    });
    await tx.query("UPDATE market_orders SET status = 'CANCELLED', remaining_units = 0 WHERE id = $1", [input.orderId]);
    return { ok: true, orderId: input.orderId, released: reservation.remaining_units, side: current.side };
  });
}

/** Expire a bounded batch of standing orders before matching. Escrow is always
 * returned through the same ledger-backed release path used by cancellation. */
export async function expireMarketOrders(repository: PostgresRepository, gameDay: number, gameMinute = END_OF_GAME_DAY_MINUTE, limit = 100): Promise<{ expired: number }> {
  return repository.transaction(async (tx) => {
    const orders = await tx.query<{ id: string; owner_economic_id: string; good_til_game_day: number }>(
      `SELECT id, owner_economic_id, good_til_game_day
         FROM market_orders
        WHERE status IN ('OPEN', 'PARTIAL') AND good_til_game_day IS NOT NULL
          AND good_til_game_day < $1
        ORDER BY good_til_game_day, created_at, id
        FOR UPDATE SKIP LOCKED LIMIT $2`, [gameDay, limit],
    );
    let expired = 0;
    for (const order of orders.rows) {
      const reservation = await getMarketReservation(tx, order.id);
      if (reservation && BigInt(reservation.remaining_units) > 0n) {
        const destination = await marketEconomicAccount(tx, order.owner_economic_id, reservation.asset_id);
        if (!destination) throw new Error(`Market expiry destination is missing for order ${order.id}`);
        await releaseReservation(tx, {
          escrowAccountId: reservation.escrow_account_id,
          destinationAccountId: destination,
          assetId: reservation.asset_id,
          amountUnits: BigInt(reservation.remaining_units),
          orderId: order.id,
          gameDay,
          settlement: { gameDay, gameMinute },
          reason: 'market_order_expiry',
        });
      }
      await tx.query("UPDATE market_orders SET status = 'CANCELLED', remaining_units = 0 WHERE id = $1 AND status IN ('OPEN', 'PARTIAL')", [order.id]);
      expired += 1;
    }
    return { expired };
  });
}
