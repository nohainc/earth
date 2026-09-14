import type { PostgresRepository } from './repository.ts';

export type MarketCandle = {
  instrument_id: string;
  interval_kind: 'hourly' | 'daily';
  period_id: string;
  open_price_units: string;
  high_price_units: string;
  low_price_units: string;
  close_price_units: string;
  volume_units: string;
  fill_count: string;
};

/** Materialize deterministic hourly and daily OHLCV candles from completed fills. */
export async function refreshMarketCandles(repository: PostgresRepository, instrumentId: string, _batchId: number): Promise<void> {
  for (const interval of ['hourly', 'daily'] as const) {
    const period = interval === 'hourly' ? '((b.game_day * 24) + FLOOR(b.game_minute / 60))::BIGINT' : 'b.game_day::BIGINT';
    const result = await repository.query<MarketCandle>(
      `SELECT $1::TEXT AS instrument_id, $2::TEXT AS interval_kind, ${period} AS period_id,
              (ARRAY_AGG(f.price_units ORDER BY b.id, f.id))[1]::TEXT AS open_price_units,
              MAX(f.price_units)::TEXT AS high_price_units,
              MIN(f.price_units)::TEXT AS low_price_units,
              (ARRAY_AGG(f.price_units ORDER BY b.id DESC, f.id DESC))[1]::TEXT AS close_price_units,
              SUM(f.quantity_units)::TEXT AS volume_units, COUNT(*)::TEXT AS fill_count
         FROM market_fills f JOIN market_batches b ON b.id = f.batch_id
        WHERE f.instrument_id = $1 AND b.status = 'COMPLETED'
        GROUP BY ${period}`, [instrumentId, interval]);
    for (const candle of result.rows) {
      await repository.query(
        `INSERT INTO market_candles
          (instrument_id, interval_kind, period_id, open_price_units, high_price_units, low_price_units, close_price_units, volume_units, fill_count)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (instrument_id, interval_kind, period_id) DO UPDATE SET
           open_price_units = EXCLUDED.open_price_units,
           high_price_units = EXCLUDED.high_price_units,
           low_price_units = EXCLUDED.low_price_units,
           close_price_units = EXCLUDED.close_price_units,
           volume_units = EXCLUDED.volume_units,
           fill_count = EXCLUDED.fill_count`,
        [instrumentId, interval, candle.period_id, candle.open_price_units, candle.high_price_units, candle.low_price_units, candle.close_price_units, candle.volume_units, candle.fill_count]);
    }
  }
}
