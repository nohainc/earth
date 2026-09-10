-- Economy V2 Plan 11: resumable settlement phase coordination.
-- Reuses daily_settlement_phase_runs; each phase can be claimed and committed
-- independently while preserving the existing ordered phase model.

ALTER TABLE daily_settlement_phase_runs
  ADD COLUMN IF NOT EXISTS lease_owner TEXT,
  ADD COLUMN IF NOT EXISTS lease_heartbeat_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS daily_settlement_phase_runs_lease_idx
  ON daily_settlement_phase_runs (status, lease_heartbeat_at);

CREATE OR REPLACE FUNCTION earth_claim_settlement_phase(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard TEXT,
  p_lease_owner TEXT,
  p_lease_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (claimed BOOLEAN, status TEXT, attempt_count INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
  current_run daily_settlement_phase_runs%ROWTYPE;
  stale_before TIMESTAMPTZ;
BEGIN
  IF p_lease_owner IS NULL OR length(btrim(p_lease_owner)) = 0 THEN
    RAISE EXCEPTION 'Settlement phase lease owner is required';
  END IF;
  IF p_lease_seconds < 1 THEN
    RAISE EXCEPTION 'Settlement phase lease must be positive';
  END IF;
  stale_before := CURRENT_TIMESTAMP - make_interval(secs => p_lease_seconds);

  INSERT INTO daily_settlement_phase_runs (
    game_day, phase, shard, status, attempt_count, lease_owner, lease_heartbeat_at
  ) VALUES (
    p_game_day, p_phase, COALESCE(p_shard, 'all'), 'running', 1, p_lease_owner, CURRENT_TIMESTAMP
  )
  ON CONFLICT (game_day, phase, shard) DO NOTHING;

  SELECT * INTO current_run
  FROM daily_settlement_phase_runs
  WHERE game_day = p_game_day AND phase = p_phase AND shard = COALESCE(p_shard, 'all')
  FOR UPDATE;

  IF current_run.status = 'completed' THEN
    claimed := FALSE; status := current_run.status; attempt_count := current_run.attempt_count; RETURN NEXT; RETURN;
  END IF;
  IF current_run.status = 'running'
     AND current_run.lease_owner = p_lease_owner
     AND COALESCE(current_run.lease_heartbeat_at, current_run.started_at) > stale_before THEN
    claimed := TRUE; status := current_run.status; attempt_count := current_run.attempt_count; RETURN NEXT; RETURN;
  END IF;
  IF current_run.status = 'running'
     AND current_run.lease_owner IS NOT NULL
     AND current_run.lease_owner <> p_lease_owner
     AND COALESCE(current_run.lease_heartbeat_at, current_run.started_at) > stale_before THEN
    claimed := FALSE; status := current_run.status; attempt_count := current_run.attempt_count; RETURN NEXT; RETURN;
  END IF;

  UPDATE daily_settlement_phase_runs
  SET status = 'running', attempt_count = current_run.attempt_count + 1,
      lease_owner = p_lease_owner, lease_heartbeat_at = CURRENT_TIMESTAMP,
      started_at = CURRENT_TIMESTAMP, completed_at = NULL, error_message = NULL
  WHERE game_day = p_game_day AND phase = p_phase AND shard = COALESCE(p_shard, 'all');
  claimed := TRUE; status := 'running'; attempt_count := current_run.attempt_count + 1;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION earth_heartbeat_settlement_phase(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard TEXT,
  p_lease_owner TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  UPDATE daily_settlement_phase_runs
  SET lease_heartbeat_at = CURRENT_TIMESTAMP
  WHERE game_day = $1 AND phase = $2 AND shard = COALESCE($3, 'all')
    AND status = 'running' AND lease_owner = $4
  RETURNING TRUE;
$$;

CREATE OR REPLACE FUNCTION earth_complete_settlement_phase(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard TEXT,
  p_lease_owner TEXT,
  p_rows_processed BIGINT DEFAULT 0
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  UPDATE daily_settlement_phase_runs
  SET status = 'completed', rows_processed = GREATEST(0, $5),
      completed_at = CURRENT_TIMESTAMP, lease_owner = NULL, lease_heartbeat_at = NULL,
      error_message = NULL
  WHERE game_day = $1 AND phase = $2 AND shard = COALESCE($3, 'all')
    AND status = 'running' AND lease_owner = $4
  RETURNING TRUE;
$$;

CREATE OR REPLACE FUNCTION earth_fail_settlement_phase(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard TEXT,
  p_lease_owner TEXT,
  p_error_message TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  UPDATE daily_settlement_phase_runs
  SET status = 'failed', error_message = left($5, 2000),
      lease_owner = NULL, lease_heartbeat_at = NULL
  WHERE game_day = $1 AND phase = $2 AND shard = COALESCE($3, 'all')
    AND status = 'running' AND lease_owner = $4
  RETURNING TRUE;
$$;
