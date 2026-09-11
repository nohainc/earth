-- Market V2 Plan 9: rebuildable instrument book/read state.
CREATE TABLE IF NOT EXISTS market_instrument_state (
  instrument_id TEXT PRIMARY KEY REFERENCES market_instruments(id),
  last_completed_batch_id BIGINT,
  last_clearing_price_units BIGINT,
  best_bid_units BIGINT,
  best_ask_units BIGINT,
  open_buy_units BIGINT NOT NULL DEFAULT 0,
  open_sell_units BIGINT NOT NULL DEFAULT 0,
  rolling_volume_units BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO market_instrument_state (instrument_id, last_clearing_price_units)
SELECT i.id, p.price_units
  FROM market_instruments i
  JOIN market_prices p ON p.product = lower(regexp_replace(i.symbol, '^SPOT-', ''))
 WHERE i.instrument_type = 'SPOT'
ON CONFLICT (instrument_id) DO UPDATE
  SET last_clearing_price_units = COALESCE(market_instrument_state.last_clearing_price_units, EXCLUDED.last_clearing_price_units);

CREATE OR REPLACE FUNCTION earth_rebuild_market_instrument_state(p_instrument_id TEXT)
RETURNS market_instrument_state
LANGUAGE plpgsql
AS $$
DECLARE rebuilt market_instrument_state%ROWTYPE;
BEGIN
  INSERT INTO market_instrument_state (instrument_id)
  VALUES (p_instrument_id)
  ON CONFLICT (instrument_id) DO NOTHING;
  WITH book AS (
    SELECT
      COALESCE(SUM(CASE WHEN side = 'buy' THEN quantity_units - filled_quantity_units ELSE 0 END) FILTER (WHERE status IN ('open','partial') AND ((side = 'buy' AND reserved_quote_units > 0) OR (side = 'sell' AND reserved_base_units > 0))), 0)::BIGINT AS buys,
      COALESCE(SUM(CASE WHEN side = 'sell' THEN quantity_units - filled_quantity_units ELSE 0 END) FILTER (WHERE status IN ('open','partial') AND ((side = 'buy' AND reserved_quote_units > 0) OR (side = 'sell' AND reserved_base_units > 0))), 0)::BIGINT AS sells,
      MAX(limit_price_units) FILTER (WHERE side = 'buy' AND status IN ('open','partial') AND reserved_quote_units > 0) AS bid,
      MIN(limit_price_units) FILTER (WHERE side = 'sell' AND status IN ('open','partial') AND reserved_base_units > 0) AS ask
    FROM market_orders WHERE instrument_id = p_instrument_id
  ), fills AS (
    SELECT MAX(price_units) FILTER (WHERE batch_id = (SELECT MAX(batch_id) FROM market_fills WHERE instrument_id = p_instrument_id))::BIGINT AS last_price,
           COALESCE(SUM(quantity_units) FILTER (WHERE batch_id >= GREATEST(0, (SELECT COALESCE(MAX(batch_id), 0) FROM market_fills WHERE instrument_id = p_instrument_id) - 23)), 0)::BIGINT AS rolling_volume
      FROM market_fills WHERE instrument_id = p_instrument_id
  ), completed AS (
    SELECT MAX(batch_id) AS batch_id FROM market_batch_instruments WHERE instrument_id = p_instrument_id AND status = 'completed'
  )
  UPDATE market_instrument_state state
     SET last_completed_batch_id = COALESCE(completed.batch_id, state.last_completed_batch_id),
         last_clearing_price_units = COALESCE(fills.last_price, state.last_clearing_price_units),
         best_bid_units = book.bid,
         best_ask_units = book.ask,
         open_buy_units = book.buys,
         open_sell_units = book.sells,
         rolling_volume_units = fills.rolling_volume,
         updated_at = CURRENT_TIMESTAMP
    FROM book, fills, completed
   WHERE state.instrument_id = p_instrument_id;
  SELECT * INTO rebuilt FROM market_instrument_state WHERE instrument_id = p_instrument_id;
  RETURN rebuilt;
END;
$$;

CREATE INDEX IF NOT EXISTS market_instrument_state_updated_idx ON market_instrument_state(updated_at);
