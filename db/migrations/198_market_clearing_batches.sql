-- Market V2 Plan 6: immutable clearing batches and instrument progress.
CREATE TABLE IF NOT EXISTS market_batches (
  id BIGINT PRIMARY KEY,
  start_total_game_minute BIGINT NOT NULL,
  end_total_game_minute BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'clearing', 'completed', 'failed')),
  rules_version TEXT NOT NULL DEFAULT 'market-v2',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  CHECK (start_total_game_minute >= 0 AND end_total_game_minute > start_total_game_minute)
);

CREATE TABLE IF NOT EXISTS market_batch_instruments (
  batch_id BIGINT NOT NULL REFERENCES market_batches(id),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'clearing', 'completed', 'failed')),
  lease_owner TEXT,
  lease_expires_at TIMESTAMPTZ,
  eligible_order_count BIGINT NOT NULL DEFAULT 0,
  fill_count BIGINT NOT NULL DEFAULT 0,
  volume_units BIGINT NOT NULL DEFAULT 0,
  previous_price_units BIGINT,
  clearing_price_units BIGINT,
  economic_transaction_id BIGINT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  PRIMARY KEY (batch_id, instrument_id)
);
CREATE INDEX IF NOT EXISTS market_batches_status_idx ON market_batches(status, id);
CREATE INDEX IF NOT EXISTS market_batch_instruments_lease_idx ON market_batch_instruments(status, lease_expires_at);

CREATE OR REPLACE FUNCTION earth_claim_market_batch_instrument(
  p_batch_id BIGINT,
  p_instrument_id TEXT,
  p_lease_owner TEXT,
  p_lease_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (claimed BOOLEAN, status TEXT)
LANGUAGE plpgsql
AS $$
DECLARE current_run market_batch_instruments%ROWTYPE;
BEGIN
  INSERT INTO market_batch_instruments (batch_id, instrument_id, status)
  VALUES (p_batch_id, p_instrument_id, 'pending')
  ON CONFLICT (batch_id, instrument_id) DO NOTHING;
  SELECT * INTO current_run FROM market_batch_instruments
   WHERE batch_id = p_batch_id AND instrument_id = p_instrument_id FOR UPDATE;
  IF current_run.status = 'completed' THEN claimed := FALSE; status := 'completed'; RETURN NEXT; RETURN; END IF;
  IF current_run.status = 'clearing' AND current_run.lease_owner <> p_lease_owner
     AND COALESCE(current_run.lease_expires_at, CURRENT_TIMESTAMP) > CURRENT_TIMESTAMP THEN
    claimed := FALSE; status := 'busy'; RETURN NEXT; RETURN;
  END IF;
  UPDATE market_batch_instruments
     SET status = 'clearing', lease_owner = p_lease_owner,
         lease_expires_at = CURRENT_TIMESTAMP + make_interval(secs => p_lease_seconds),
         started_at = COALESCE(started_at, CURRENT_TIMESTAMP), error_message = NULL
   WHERE batch_id = p_batch_id AND instrument_id = p_instrument_id;
  claimed := TRUE; status := 'clearing'; RETURN NEXT;
END;
$$;
