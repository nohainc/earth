import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { enqueueOutbox } from './outbox-postgres';
import { centsToMoney, marketValueToCents, moneyToCents, rateAmountToCents } from './money';
import { fromNanoMarkup } from './nano-markup.ts';

type MarketOrderInput = {
  humanId: string;
  product: string;
  side: 'buy' | 'sell';
  quantity: number;
  limitPrice: number;
  correlationId: string;
};

const products = new Set(['material', 'components', 'energy', 'compute']);

async function feeRate(repository: PostgresRepository): Promise<string> {
  const result = await repository.query<{ rate: string }>("SELECT rate FROM tax_rules WHERE scope = 'global' AND category = 'market' AND active = true LIMIT 1");
  return result.rows[0]?.rate ?? '0';
}

export async function submitMarketOrder(repository: PostgresRepository, input: MarketOrderInput): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM market_orders WHERE human_id = $1 AND correlation_id = $2', [input.humanId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, order: prior.rows[0], correlationId: input.correlationId };
    const human = await tx.query('SELECT id FROM humans WHERE id = $1', [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const rate = input.side === 'buy' ? await feeRate(tx) : '0';
    const reservedCents = input.side === 'buy' ? marketValueToCents(input.quantity, input.limitPrice) + rateAmountToCents(marketValueToCents(input.quantity, input.limitPrice), rate) : 0n;
    const reserved = input.side === 'buy' ? centsToMoney(reservedCents) : '0.00';
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const orderId = crypto.randomUUID();
    const escrowAccount = `market-order-${orderId}`;
    if (input.side === 'sell') {
      const inventory = await tx.query<{ amount: string }>('SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE', [input.humanId, input.product]);
      if (!inventory.rows[0] || Number(inventory.rows[0].amount) < input.quantity) throw new Error(`Insufficient ${input.product} inventory`);
      await tx.query('UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1', [input.quantity, input.humanId, input.product]);
    } else {
      const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.humanId]);
      if (!account.rows[0] || moneyToCents(account.rows[0].balance) < reservedCents) throw new Error('Insufficient Credits to reserve this order');
      await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $1, 0, 'CREDIT')", [escrowAccount]);
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: account.rows[0].account_id, creditAccount: escrowAccount, amount: reserved, reasonType: 'market_order_reservation', reasonId: orderId, ruleVersion: 'market-v4', correlationId: input.correlationId });
    }
    await tx.query('INSERT INTO market_orders (id, human_id, product, side, quantity, limit_price, reserved_credits, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)', [orderId, input.humanId, input.product, input.side, input.quantity, centsToMoney(moneyToCents(input.limitPrice)), reserved, input.correlationId]);
    await tx.query(`UPDATE market_prices SET ${input.side === 'sell' ? 'supply' : 'demand'} = ${input.side === 'sell' ? 'supply' : 'demand'} + $1 WHERE product = $2`, [input.quantity, input.product]);
    const order = await tx.query('SELECT * FROM market_orders WHERE id = $1', [orderId]);
    return { ok: true, order: order.rows[0], correlationId: input.correlationId };
  });
}

export async function settleMarket(repository: PostgresRepository, product: string): Promise<Record<string, unknown>> {
  if (!products.has(product)) throw new Error('Unknown product');
  return repository.transaction(async (tx) => {
    const price = await tx.query<{ price: string; supply: string }>('SELECT * FROM market_prices WHERE product = $1 FOR UPDATE', [product]);
    const buy = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE product = $1 AND side = 'buy' AND status IN ('open','partial') AND reserved_credits > 0 AND limit_price >= $2 ORDER BY filled_quantity ASC, created_at ASC LIMIT 1 FOR UPDATE", [product, price.rows[0]?.price ?? 0]);
    const sell = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE product = $1 AND side = 'sell' AND status IN ('open','partial') AND limit_price <= $2 ORDER BY filled_quantity ASC, created_at ASC LIMIT 1 FOR UPDATE", [product, price.rows[0]?.price ?? 0]);
    if (!price.rows[0] || !buy.rows[0] || !sell.rows[0] || buy.rows[0].human_id === sell.rows[0].human_id) return { ok: true, filled: false, reason: 'No eligible matched orders or price' };
    const buyOrder = buy.rows[0]; const sellOrder = sell.rows[0];
    const fill = Math.min(Number(buyOrder.quantity) - Number(buyOrder.filled_quantity), Number(sellOrder.quantity) - Number(sellOrder.filled_quantity), Number(price.rows[0].supply));
    if (fill <= 0) return { ok: true, filled: false, reason: 'No available supply' };
    const clearingPrice = centsToMoney(moneyToCents(price.rows[0].price));
    const totalCents = marketValueToCents(fill, clearingPrice);
    const rate = await feeRate(tx);
    const feeCents = rateAmountToCents(totalCents, rate);
    const payableCents = totalCents + feeCents;
    const reservedCents = moneyToCents(buyOrder.reserved_credits ?? '0');
    const usedCents = reservedCents > 0n ? marketValueToCents(fill, buyOrder.limit_price) + rateAmountToCents(marketValueToCents(fill, buyOrder.limit_price), rate) : payableCents;
    if (reservedCents > 0n && reservedCents < usedCents) throw new Error('Buy order reservation is inconsistent');
    const game = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(game.rows[0]?.game_day ?? 0);
    const tradeId = crypto.randomUUID();
    const buyFilled = Number(buyOrder.filled_quantity) + fill;
    const sellFilled = Number(sellOrder.filled_quantity) + fill;
    const refund = usedCents > payableCents ? centsToMoney(usedCents - payableCents) : '0.00';
    const fee = centsToMoney(feeCents);
    const total = centsToMoney(totalCents);
    const payable = centsToMoney(payableCents);
    const used = centsToMoney(usedCents);
    const escrowAccount = `market-order-${buyOrder.id}`;
    const escrow = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE account_id = $1 AND currency = 'CREDIT' FOR UPDATE", [escrowAccount]);
    if (!escrow.rows[0]) throw new Error('Market order escrow is missing');
    const settlementAccounts = await tx.query<{ account_id: string; owner_id: string }>("SELECT account_id, owner_id FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT'", [String(buyOrder.human_id), String(sellOrder.human_id)]);
    const buyerAccount = settlementAccounts.rows.find((row) => row.owner_id === String(buyOrder.human_id));
    const sellerAccount = settlementAccounts.rows.find((row) => row.owner_id === String(sellOrder.human_id));
    if (!buyerAccount || !sellerAccount) throw new Error('Market settlement accounts are missing');
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: escrowAccount, creditAccount: sellerAccount.account_id, amount: total, reasonType: 'market_trade', reasonId: String(buyOrder.id), ruleVersion: 'market-v4', correlationId: tradeId });
    if (feeCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: escrowAccount, creditAccount: 'account-ouc-treasury', amount: fee, reasonType: 'market_fee', reasonId: String(buyOrder.id), ruleVersion: 'market-v4', correlationId: tradeId });
    if (refund !== '0.00') await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: escrowAccount, creditAccount: buyerAccount.account_id, amount: refund, reasonType: 'market_order_refund', reasonId: String(buyOrder.id), ruleVersion: 'market-v4', correlationId: tradeId });
    await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [buyOrder.human_id, product, fill]);
    await tx.query("UPDATE market_orders SET filled_quantity = $1, reserved_credits = GREATEST(0, reserved_credits - $2), status = $3 WHERE id = $4", [buyFilled, used, buyFilled >= Number(buyOrder.quantity) ? 'filled' : 'partial', buyOrder.id]);
    await tx.query("UPDATE market_orders SET filled_quantity = $1, status = $2 WHERE id = $3", [sellFilled, sellFilled >= Number(sellOrder.quantity) ? 'filled' : 'partial', sellOrder.id]);
    await tx.query('UPDATE market_prices SET supply = supply - $1, demand = GREATEST(0, demand - $1), game_day = $2 WHERE product = $3', [fill, gameDay, product]);
    await tx.query('INSERT INTO market_trades (id, order_id, product, quantity, clearing_price, game_day) VALUES ($1,$2,$3,$4,$5,$6)', [tradeId, buyOrder.id, product, fill, clearingPrice, gameDay]);
    if (buyFilled >= Number(buyOrder.quantity)) {
      const removedEscrow = await tx.query('DELETE FROM account_balances WHERE account_id = $1 AND balance = 0', [escrowAccount]);
      if (removedEscrow.rowCount !== 1) throw new Error('Market order escrow did not settle to zero');
    }
    await enqueueOutbox(tx, {
      eventKey: `market-trade:${tradeId}`,
      topic: 'world_activity',
      aggregateType: 'market_trade',
      aggregateId: tradeId,
      payload: { type: 'world_activity', gameDay, category: 'market', tradeId, product, quantity: fill },
    });
    return { ok: true, filled: true, buyOrderId: buyOrder.id, sellOrderId: sellOrder.id, tradeId, product, quantity: fill, clearingPrice: Number(clearingPrice), total: Number(total), fee: Number(fee), payable: Number(payable) };
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
    const order = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE id = $1 AND human_id = $2 AND status IN ('open','partial') FOR UPDATE", [input.orderId, input.humanId]);
    if (!order.rows[0]) throw new Error('Open order not found for this Human');
    const current = order.rows[0];
    const remaining = Number(current.quantity) - Number(current.filled_quantity);
    if (String(current.side) === 'sell') {
      await tx.query('INSERT INTO resource_balances (owner_id,resource,amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + excluded.amount', [input.humanId, current.product, remaining]);
      await tx.query('UPDATE market_prices SET supply = GREATEST(0, supply - $1) WHERE product = $2', [remaining, current.product]);
    } else {
      const escrowAccount = `market-order-${current.id}`;
      const escrow = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE account_id = $1 AND currency = 'CREDIT' FOR UPDATE", [escrowAccount]);
      if (!escrow.rows[0]) throw new Error('Market order escrow is missing');
      const buyerAccount = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [String(current.human_id)]);
      if (!buyerAccount.rows[0]) throw new Error('Market order buyer account is missing');
      const day = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
      if (moneyToCents(current.reserved_credits ?? '0.00') > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: escrowAccount, creditAccount: buyerAccount.rows[0].account_id, amount: String(current.reserved_credits ?? '0.00'), reasonType: 'market_order_cancellation', reasonId: String(current.id), ruleVersion: 'market-v4', correlationId: `CANCEL-${input.orderId}` });
      const removedEscrow = await tx.query('DELETE FROM account_balances WHERE account_id = $1 AND balance = 0', [escrowAccount]);
      if (removedEscrow.rowCount !== 1) throw new Error('Market order escrow did not refund to zero');
      await tx.query('UPDATE market_prices SET demand = GREATEST(0, demand - $1) WHERE product = $2', [remaining, current.product]);
    }
    await tx.query("UPDATE market_orders SET status = 'cancelled', reserved_credits = 0 WHERE id = $1 AND human_id = $2", [input.orderId, input.humanId]);
    return { ok: true, orderId: input.orderId, released: remaining, side: current.side };
  });
}
