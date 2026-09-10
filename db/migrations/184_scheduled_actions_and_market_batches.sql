-- Plan 4: lease timed actions and process markets by game-time batches.

ALTER TABLE scheduled_actions
  ADD COLUMN IF NOT EXISTS lease_owner TEXT,
  ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
ALTER TABLE market_prices ADD COLUMN IF NOT EXISTS last_market_batch_id BIGINT;

CREATE INDEX IF NOT EXISTS scheduled_actions_lease_idx
  ON scheduled_actions(status, lease_expires_at);

CREATE OR REPLACE FUNCTION earth_claim_scheduled_actions(
  p_game_day BIGINT,
  p_game_minute INTEGER,
  p_lease_owner TEXT,
  p_limit INTEGER DEFAULT 100,
  p_lease_seconds INTEGER DEFAULT 300,
  p_action_type TEXT DEFAULT NULL
)
RETURNS SETOF scheduled_actions
LANGUAGE sql
AS $$
  WITH candidates AS (
    SELECT id
    FROM scheduled_actions
    WHERE (status = 'pending' OR (status = 'running' AND lease_expires_at < CURRENT_TIMESTAMP))
      AND ($6 IS NULL OR action_type = $6)
      AND (due_game_day, due_game_minute) <= ($1, $2)
    ORDER BY priority, due_game_day, due_game_minute, created_at, id
    FOR UPDATE SKIP LOCKED
    LIMIT $4
  )
  UPDATE scheduled_actions a
  SET status = 'running', lease_owner = $3, lease_expires_at = CURRENT_TIMESTAMP + make_interval(secs => $5),
      claimed_at = CURRENT_TIMESTAMP, started_at = CURRENT_TIMESTAMP,
      attempt_count = attempt_count + 1, updated_at = CURRENT_TIMESTAMP
  FROM candidates c
  WHERE a.id = c.id
  RETURNING a.*;
$$;

CREATE TABLE IF NOT EXISTS market_batch_runs (
  batch_id BIGINT NOT NULL,
  product TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed')),
  lease_owner TEXT,
  lease_expires_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  orders_processed BIGINT NOT NULL DEFAULT 0,
  trades_created BIGINT NOT NULL DEFAULT 0,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (batch_id, product)
);
CREATE INDEX IF NOT EXISTS market_batch_runs_status_idx ON market_batch_runs(status, batch_id);

CREATE OR REPLACE FUNCTION earth_claim_market_batch(
  p_batch_id BIGINT,
  p_product TEXT,
  p_lease_owner TEXT,
  p_lease_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (claimed BOOLEAN, status TEXT)
LANGUAGE plpgsql
AS $$
DECLARE current_run market_batch_runs%ROWTYPE;
BEGIN
  INSERT INTO market_batch_runs (batch_id, product, status)
  VALUES (p_batch_id, p_product, 'pending')
  ON CONFLICT (batch_id, product) DO NOTHING;
  SELECT * INTO current_run FROM market_batch_runs WHERE batch_id = p_batch_id AND product = p_product FOR UPDATE;
  IF current_run.status = 'completed' THEN claimed := FALSE; status := 'completed'; RETURN NEXT; RETURN; END IF;
  IF current_run.status = 'running' AND current_run.lease_owner <> p_lease_owner
     AND COALESCE(current_run.lease_expires_at, CURRENT_TIMESTAMP) > CURRENT_TIMESTAMP THEN
    claimed := FALSE; status := 'busy'; RETURN NEXT; RETURN;
  END IF;
  UPDATE market_batch_runs
  SET status = 'running', lease_owner = p_lease_owner,
      lease_expires_at = CURRENT_TIMESTAMP + make_interval(secs => 300),
      started_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP, error_message = NULL
  WHERE batch_id = p_batch_id AND product = p_product;
  claimed := TRUE; status := 'running'; RETURN NEXT;
END;
$$;
