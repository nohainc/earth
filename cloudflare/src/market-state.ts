import type { PostgresRepository } from './repository.ts';

export type MarketInstrumentState = {
  instrument_id: string;
  last_completed_batch_id: string | null;
  last_clearing_price_units: string | null;
  best_bid_units: string | null;
  best_ask_units: string | null;
  open_buy_units: string;
  open_sell_units: string;
  rolling_volume_units: string;
  updated_at: string;
};

/** Rebuild the market read model from open orders and immutable fills. */
export async function rebuildMarketInstrumentState(
  repository: PostgresRepository,
  instrumentId: string,
): Promise<MarketInstrumentState> {
  const result = await repository.query<MarketInstrumentState>(
    'SELECT * FROM earth_rebuild_market_instrument_state($1)',
    [instrumentId],
  );
  if (!result.rows[0]) throw new Error(`Unable to rebuild market state for ${instrumentId}`);
  return result.rows[0];
}

/** Keep the legacy market_prices row usable for transitional readers only. */
export async function refreshMarketPriceProjection(
  repository: PostgresRepository,
  instrument: { id: string; product: string },
  state: MarketInstrumentState,
  gameDay: number,
): Promise<void> {
  await repository.query(
    `UPDATE market_prices
        SET price_units = COALESCE($1, price_units),
            price = COALESCE($1, price_units) / 100.0,
            supply_units = $2,
            demand_units = $3,
            supply = $2 / 1000000.0,
            demand = $3 / 1000000.0,
            game_day = $4,
            last_market_batch_id = $5
      WHERE product = $6`,
    [state.last_clearing_price_units, state.open_sell_units, state.open_buy_units, gameDay, state.last_completed_batch_id, instrument.product],
  );
}
