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
  _repository: PostgresRepository,
  _instrumentId: string,
  _batchId: number,
): Promise<void> {
  // Candle materialization is a later projection concern; the clean market
  // source of truth is market_fills and market_instrument_state.
}
