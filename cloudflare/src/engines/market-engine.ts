import type { PostgresRepository } from '../repository.ts';
import { settleMarket } from '../market-postgres.ts';
import { listActiveSpotProducts } from '../market-model.ts';
import { rebuildMarketInstrumentState } from '../market-state.ts';
import { getActiveSpotInstrument } from '../market-model.ts';

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

  for (const product of await listActiveSpotProducts(repo)) {
    const result = await settleMarket(repo, product);
    if (result.filled) settledOrders += 1;

    const instrument = await getActiveSpotInstrument(repo, product);
    const state = instrument ? await rebuildMarketInstrumentState(repo, instrument.id) : null;
    updatedPrices[product] = Number(state?.last_clearing_price_units ?? 0) / 100 || 10;
  }

  return { settledOrders, updatedPrices };
}
