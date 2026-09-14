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
    `WITH open_orders AS (
       SELECT COALESCE(SUM(CASE WHEN side = 'BUY' THEN remaining_units ELSE 0 END), 0)::TEXT AS open_buy_units,
              COALESCE(SUM(CASE WHEN side = 'SELL' THEN remaining_units ELSE 0 END), 0)::TEXT AS open_sell_units
         FROM market_orders WHERE instrument_id = $1 AND status IN ('OPEN','PARTIAL')
     )
     SELECT $1::TEXT AS instrument_id, MAX(f.batch_id)::TEXT AS last_completed_batch_id,
            NULL::TEXT AS last_clearing_price_units, NULL::TEXT AS best_bid_units, NULL::TEXT AS best_ask_units,
            open_orders.open_buy_units, open_orders.open_sell_units, COALESCE(SUM(f.quantity_units), 0)::TEXT AS rolling_volume_units,
            CURRENT_TIMESTAMP AS updated_at
       FROM open_orders LEFT JOIN market_fills f ON f.instrument_id = $1 GROUP BY open_orders.open_buy_units, open_orders.open_sell_units`,
    [instrumentId],
  );
  if (!result.rows[0]) throw new Error(`Unable to rebuild market state for ${instrumentId}`);
  return result.rows[0];
}

/** The clean market schema keeps state in market_instrument_state. */
export async function refreshMarketPriceProjection(
  repository: PostgresRepository,
  _instrument: { id: string },
  _state: MarketInstrumentState,
  _gameDay: number,
): Promise<void> {
  // market_instrument_state is the authoritative clean projection. The
  // caller rebuilds it directly from market_orders and market_fills.
}
