import type { PostgresRepository } from '../repository.ts';
import { settleMarket } from '../market-postgres.ts';

const PRODUCTS = ['food', 'material', 'components', 'energy', 'compute'];

export interface MarketSettlementResult {
  settledOrders: number;
  updatedPrices: Record<string, number>;
}

export async function settleContinuousMarket(
  repo: PostgresRepository,
  gameDay: number,
): Promise<MarketSettlementResult> {
  let settledOrders = 0;
  const updatedPrices: Record<string, number> = {};

  for (const product of PRODUCTS) {
    const result = await settleMarket(repo, product);
    if (result.filled) settledOrders += 1;

    // Apply continuous price drift toward supply/demand equilibrium
    await repo.query(
      `UPDATE market_prices
       SET price = GREATEST(1, LEAST(1000000, ROUND((price * (1.0 + LEAST(0.05, GREATEST(-0.05, (demand - supply) / GREATEST(1.0, supply + demand)))))::numeric, 2))),
           game_day = $1
       WHERE product = $2`,
      [gameDay, product],
    );

    const priceRow = await repo.query<{ price: string }>('SELECT price FROM market_prices WHERE product = $1', [product]);
    updatedPrices[product] = Number(priceRow.rows[0]?.price ?? 10);
  }

  return { settledOrders, updatedPrices };
}
