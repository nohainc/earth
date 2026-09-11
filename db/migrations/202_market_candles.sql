-- Market V2 Plan 10: OHLC read models derived from completed fills.
CREATE TABLE IF NOT EXISTS market_candles (
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  interval_kind TEXT NOT NULL CHECK (interval_kind IN ('hourly', 'daily')),
  period_id BIGINT NOT NULL,
  open_price_units BIGINT NOT NULL CHECK (open_price_units > 0),
  high_price_units BIGINT NOT NULL CHECK (high_price_units > 0),
  low_price_units BIGINT NOT NULL CHECK (low_price_units > 0),
  close_price_units BIGINT NOT NULL CHECK (close_price_units > 0),
  volume_units BIGINT NOT NULL CHECK (volume_units >= 0),
  fill_count BIGINT NOT NULL CHECK (fill_count >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (instrument_id, interval_kind, period_id)
);

CREATE INDEX IF NOT EXISTS market_candles_lookup_idx
  ON market_candles(instrument_id, interval_kind, period_id DESC);

CREATE OR REPLACE FUNCTION earth_refresh_market_candles(
  p_instrument_id TEXT,
  p_batch_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  candle_day BIGINT;
BEGIN
  SELECT MIN(game_day) INTO candle_day
    FROM market_fills f
    JOIN market_batch_instruments mbi
      ON mbi.batch_id = f.batch_id
     AND mbi.instrument_id = f.instrument_id
     AND mbi.status = 'completed'
   WHERE f.instrument_id = p_instrument_id
     AND f.batch_id = p_batch_id;

  IF candle_day IS NULL THEN
    RETURN;
  END IF;

  WITH fills AS (
    SELECT f.batch_id, f.game_day, f.game_minute, f.sequence_no, f.id,
           f.price_units, f.quantity_units
      FROM market_fills f
      JOIN market_batch_instruments mbi
        ON mbi.batch_id = f.batch_id
       AND mbi.instrument_id = f.instrument_id
       AND mbi.status = 'completed'
     WHERE f.instrument_id = p_instrument_id
       AND f.batch_id = p_batch_id
  ), aggregate AS (
    SELECT MIN(price_units) AS low_price,
           MAX(price_units) AS high_price,
           SUM(quantity_units)::BIGINT AS volume,
           COUNT(*)::BIGINT AS fills,
           (ARRAY_AGG(price_units ORDER BY game_minute, sequence_no, id))[1] AS open_price,
           (ARRAY_AGG(price_units ORDER BY game_minute DESC, sequence_no DESC, id DESC))[1] AS close_price
      FROM fills
  )
  INSERT INTO market_candles (
    instrument_id, interval_kind, period_id,
    open_price_units, high_price_units, low_price_units, close_price_units,
    volume_units, fill_count
  )
  SELECT p_instrument_id, 'hourly', p_batch_id,
         open_price, high_price, low_price, close_price, volume, fills
    FROM aggregate
   WHERE fills > 0
  ON CONFLICT (instrument_id, interval_kind, period_id) DO UPDATE
    SET open_price_units = EXCLUDED.open_price_units,
        high_price_units = EXCLUDED.high_price_units,
        low_price_units = EXCLUDED.low_price_units,
        close_price_units = EXCLUDED.close_price_units,
        volume_units = EXCLUDED.volume_units,
        fill_count = EXCLUDED.fill_count,
        updated_at = CURRENT_TIMESTAMP;

  WITH fills AS (
    SELECT f.game_day, f.game_minute, f.sequence_no, f.id,
           f.price_units, f.quantity_units
      FROM market_fills f
      JOIN market_batch_instruments mbi
        ON mbi.batch_id = f.batch_id
       AND mbi.instrument_id = f.instrument_id
       AND mbi.status = 'completed'
     WHERE f.instrument_id = p_instrument_id
       AND f.game_day = candle_day
  ), aggregate AS (
    SELECT MIN(price_units) AS low_price,
           MAX(price_units) AS high_price,
           SUM(quantity_units)::BIGINT AS volume,
           COUNT(*)::BIGINT AS fills,
           (ARRAY_AGG(price_units ORDER BY game_minute, sequence_no, id))[1] AS open_price,
           (ARRAY_AGG(price_units ORDER BY game_minute DESC, sequence_no DESC, id DESC))[1] AS close_price
      FROM fills
  )
  INSERT INTO market_candles (
    instrument_id, interval_kind, period_id,
    open_price_units, high_price_units, low_price_units, close_price_units,
    volume_units, fill_count
  )
  SELECT p_instrument_id, 'daily', candle_day,
         open_price, high_price, low_price, close_price, volume, fills
    FROM aggregate
   WHERE fills > 0
  ON CONFLICT (instrument_id, interval_kind, period_id) DO UPDATE
    SET open_price_units = EXCLUDED.open_price_units,
        high_price_units = EXCLUDED.high_price_units,
        low_price_units = EXCLUDED.low_price_units,
        close_price_units = EXCLUDED.close_price_units,
        volume_units = EXCLUDED.volume_units,
        fill_count = EXCLUDED.fill_count,
        updated_at = CURRENT_TIMESTAMP;
END;
$$;
