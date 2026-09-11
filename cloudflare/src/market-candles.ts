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

/** Refresh hourly and daily candles after the batch/instrument is completed. */
export async function refreshMarketCandles(
  repository: PostgresRepository,
  instrumentId: string,
  batchId: number,
): Promise<void> {
  await repository.query('SELECT earth_refresh_market_candles($1, $2)', [instrumentId, batchId]);
}

