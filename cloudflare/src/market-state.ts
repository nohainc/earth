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
  genesis_reference_price_units: string;
  updated_at: string;
};

/** Rebuild and persist the authoritative market signal projection. */
export async function rebuildMarketInstrumentState(repository: PostgresRepository, instrumentId: string): Promise<MarketInstrumentState> {
  const result = await repository.query<MarketInstrumentState>(
    `WITH open_orders AS (
       SELECT COALESCE(SUM(CASE WHEN side = 'BUY' THEN remaining_units ELSE 0 END), 0)::TEXT AS open_buy_units,
              COALESCE(SUM(CASE WHEN side = 'SELL' THEN remaining_units ELSE 0 END), 0)::TEXT AS open_sell_units
         FROM market_orders WHERE instrument_id = $1 AND status IN ('OPEN','PARTIAL')
     ), latest_fill AS (
       SELECT f.price_units, f.batch_id FROM market_fills f
        JOIN market_batches b ON b.id = f.batch_id AND b.status = 'COMPLETED'
       WHERE f.instrument_id = $1 ORDER BY f.batch_id DESC, f.id DESC LIMIT 1
     ), fills AS (
       SELECT COALESCE(SUM(quantity_units), 0)::TEXT AS rolling_volume_units
         FROM market_fills WHERE instrument_id = $1
     )
     SELECT $1::TEXT AS instrument_id, latest_fill.batch_id::TEXT AS last_completed_batch_id,
            latest_fill.price_units::TEXT AS last_clearing_price_units,
            (SELECT MAX(limit_price_units)::TEXT FROM market_orders WHERE instrument_id = $1 AND side = 'BUY' AND status IN ('OPEN','PARTIAL')) AS best_bid_units,
            (SELECT MIN(limit_price_units)::TEXT FROM market_orders WHERE instrument_id = $1 AND side = 'SELL' AND status IN ('OPEN','PARTIAL')) AS best_ask_units,
            open_orders.open_buy_units, open_orders.open_sell_units, fills.rolling_volume_units,
            i.genesis_reference_price_units::TEXT, CURRENT_TIMESTAMP AS updated_at
       FROM open_orders CROSS JOIN fills CROSS JOIN market_instruments i
       LEFT JOIN latest_fill ON TRUE
      WHERE i.id = $1`, [instrumentId]);
  if (!result.rows[0]) throw new Error(`Unable to rebuild market state for ${instrumentId}`);
  const state = result.rows[0];
  await repository.query(
    `INSERT INTO market_instrument_state
      (instrument_id, last_completed_batch_id, last_clearing_price_units, best_bid_units, best_ask_units, open_buy_units, open_sell_units, rolling_volume_units, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,CURRENT_TIMESTAMP)
     ON CONFLICT (instrument_id) DO UPDATE SET
       last_completed_batch_id = EXCLUDED.last_completed_batch_id,
       last_clearing_price_units = EXCLUDED.last_clearing_price_units,
       best_bid_units = EXCLUDED.best_bid_units,
       best_ask_units = EXCLUDED.best_ask_units,
       open_buy_units = EXCLUDED.open_buy_units,
       open_sell_units = EXCLUDED.open_sell_units,
       rolling_volume_units = EXCLUDED.rolling_volume_units,
       updated_at = CURRENT_TIMESTAMP`,
    [instrumentId, state.last_completed_batch_id, state.last_clearing_price_units, state.best_bid_units, state.best_ask_units, state.open_buy_units, state.open_sell_units, state.rolling_volume_units],
  );
  return state;
}

export async function refreshMarketPriceProjection(repository: PostgresRepository, instrument: { id: string }, _state: MarketInstrumentState, _gameDay: number): Promise<void> {
  await rebuildMarketInstrumentState(repository, instrument.id);
}
