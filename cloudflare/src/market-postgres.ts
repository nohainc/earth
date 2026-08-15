import type { PostgresRepository } from './repository';
import { enqueueOutbox } from './outbox-postgres';

type MarketOrderInput = {
  humanId: string;
  product: string;
  side: 'buy' | 'sell';
  quantity: number;
  limitPrice: number;
  correlationId: string;
};

const products = new Set(['material', 'components', 'energy', 'compute']);

async function feeRate(repository: PostgresRepository): Promise<number> {
  const result = await repository.query<{ value_json: unknown }>("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1");
  const value = result.rows[0]?.value_json;
  if (!value) return 0;
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : value as { feeRate?: number };
    return typeof parsed.feeRate === 'number' && parsed.feeRate >= 0 && parsed.feeRate <= 0.05 ? parsed.feeRate : 0;
  } catch { return 0; }
}

export async function submitMarketOrder(repository: PostgresRepository, input: MarketOrderInput): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM market_orders WHERE human_id = $1 AND correlation_id = $2', [input.humanId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, order: prior.rows[0], correlationId: input.correlationId };
    const human = await tx.query('SELECT id FROM humans WHERE id = $1', [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const rate = input.side === 'buy' ? await feeRate(tx) : 0;
    const reserved = input.side === 'buy' ? Math.round(input.quantity * input.limitPrice * (1 + rate) * 100) / 100 : 0;
    if (input.side === 'sell') {
      const inventory = await tx.query<{ amount: string }>('SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE', [input.humanId, input.product]);
      if (!inventory.rows[0] || Number(inventory.rows[0].amount) < input.quantity) throw new Error(`Insufficient ${input.product} inventory`);
      await tx.query('UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1', [input.quantity, input.humanId, input.product]);
    } else {
      const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.humanId]);
      if (!account.rows[0] || Number(account.rows[0].balance) < reserved) throw new Error('Insufficient Credits to reserve this order');
      await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [reserved, account.rows[0].account_id]);
    }
    const orderId = crypto.randomUUID();
    await tx.query('INSERT INTO market_orders (id, human_id, product, side, quantity, limit_price, reserved_credits, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)', [orderId, input.humanId, input.product, input.side, input.quantity, input.limitPrice, reserved, input.correlationId]);
    await tx.query(`UPDATE market_prices SET ${input.side === 'sell' ? 'supply' : 'demand'} = ${input.side === 'sell' ? 'supply' : 'demand'} + $1 WHERE product = $2`, [input.quantity, input.product]);
    const order = await tx.query('SELECT * FROM market_orders WHERE id = $1', [orderId]);
    return { ok: true, order: order.rows[0], correlationId: input.correlationId };
  });
}

export async function settleMarket(repository: PostgresRepository, product: string): Promise<Record<string, unknown>> {
  if (!products.has(product)) throw new Error('Unknown product');
  return repository.transaction(async (tx) => {
    const price = await tx.query<{ price: string; supply: string }>('SELECT * FROM market_prices WHERE product = $1 FOR UPDATE', [product]);
    const buy = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE product = $1 AND side = 'buy' AND status IN ('open','partial') AND limit_price >= $2 ORDER BY filled_quantity ASC, created_at ASC LIMIT 1 FOR UPDATE", [product, price.rows[0]?.price ?? 0]);
    const sell = await tx.query<Record<string, unknown>>("SELECT * FROM market_orders WHERE product = $1 AND side = 'sell' AND status IN ('open','partial') AND limit_price <= $2 ORDER BY filled_quantity ASC, created_at ASC LIMIT 1 FOR UPDATE", [product, price.rows[0]?.price ?? 0]);
    if (!price.rows[0] || !buy.rows[0] || !sell.rows[0] || buy.rows[0].human_id === sell.rows[0].human_id) return { ok: true, filled: false, reason: 'No eligible matched orders or price' };
    const buyOrder = buy.rows[0]; const sellOrder = sell.rows[0];
    const fill = Math.min(Number(buyOrder.quantity) - Number(buyOrder.filled_quantity), Number(sellOrder.quantity) - Number(sellOrder.filled_quantity), Number(price.rows[0].supply));
    if (fill <= 0) return { ok: true, filled: false, reason: 'No available supply' };
    const clearingPrice = Number(price.rows[0].price);
    const total = Math.round(fill * clearingPrice * 100) / 100;
    const fee = Math.round(total * await feeRate(tx) * 100) / 100;
    const payable = total + fee;
    const reserved = Number(buyOrder.reserved_credits ?? 0);
    const used = reserved > 0 ? Math.round(fill * Number(buyOrder.limit_price) * (1 + fee / Math.max(total, 0.01)) * 100) / 100 : payable;
    if (reserved > 0 && reserved < used) throw new Error('Buy order reservation is inconsistent');
    const game = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(game.rows[0]?.game_day ?? 0);
    const tradeId = crypto.randomUUID();
    const buyFilled = Number(buyOrder.filled_quantity) + fill;
    const sellFilled = Number(sellOrder.filled_quantity) + fill;
    await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE owner_id = $2 AND currency = 'CREDIT'", [Math.max(0, used - payable), buyOrder.human_id]);
    await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE account_id = 'account-ouc-treasury'", [fee]);
    await tx.query('UPDATE account_balances SET balance = balance + $1 WHERE owner_id = $2', [total, sellOrder.human_id]);
    await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [buyOrder.human_id, product, fill]);
    await tx.query("UPDATE market_orders SET filled_quantity = $1, reserved_credits = GREATEST(0, reserved_credits - $2), status = $3 WHERE id = $4", [buyFilled, used, buyFilled >= Number(buyOrder.quantity) ? 'filled' : 'partial', buyOrder.id]);
    await tx.query("UPDATE market_orders SET filled_quantity = $1, status = $2 WHERE id = $3", [sellFilled, sellFilled >= Number(sellOrder.quantity) ? 'filled' : 'partial', sellOrder.id]);
    await tx.query('UPDATE market_prices SET supply = supply - $1, demand = GREATEST(0, demand - $1), game_day = $2 WHERE product = $3', [fill, gameDay, product]);
    await tx.query('INSERT INTO market_trades (id, order_id, product, quantity, clearing_price, game_day) VALUES ($1,$2,$3,$4,$5,$6)', [tradeId, buyOrder.id, product, fill, clearingPrice, gameDay]);
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [tradeId, gameDay, buyOrder.human_id, sellOrder.human_id, total, 'CREDIT', 'market_trade', buyOrder.id, 'market-v3', tradeId]);
    if (fee > 0) await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [crypto.randomUUID(), gameDay, buyOrder.human_id, 'account-ouc-treasury', fee, 'CREDIT', 'market_fee', buyOrder.id, 'market-v3', tradeId]);
    await enqueueOutbox(tx, {
      eventKey: `market-trade:${tradeId}`,
      topic: 'world_activity',
      aggregateType: 'market_trade',
      aggregateId: tradeId,
      payload: { type: 'world_activity', gameDay, category: 'market', tradeId, product, quantity: fill },
    });
    return { ok: true, filled: true, buyOrderId: buyOrder.id, sellOrderId: sellOrder.id, tradeId, product, quantity: fill, clearingPrice, total, fee, payable };
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
      await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE owner_id = $2 AND currency = 'CREDIT'", [Number(current.reserved_credits ?? 0), input.humanId]);
      await tx.query('UPDATE market_prices SET demand = GREATEST(0, demand - $1) WHERE product = $2', [remaining, current.product]);
    }
    await tx.query("UPDATE market_orders SET status = 'cancelled', reserved_credits = 0 WHERE id = $1 AND human_id = $2", [input.orderId, input.humanId]);
    return { ok: true, orderId: input.orderId, released: remaining, side: current.side };
  });
}
