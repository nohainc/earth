-- Plan 2: coordinate ownership of an entire settlement day.
-- A running day may only be taken over after its lease is stale.

CREATE OR REPLACE FUNCTION earth_claim_settlement_day(
  p_game_day BIGINT,
  p_lease_owner TEXT,
  p_lease_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (claimed BOOLEAN, status TEXT, attempt_count INTEGER, current_phase TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  current_run daily_settlement_runs%ROWTYPE;
  stale_before TIMESTAMPTZ;
BEGIN
  IF p_game_day IS NULL OR p_game_day < 1 THEN
    RAISE EXCEPTION 'Settlement day must be positive';
  END IF;
  IF p_lease_owner IS NULL OR length(btrim(p_lease_owner)) = 0 THEN
    RAISE EXCEPTION 'Settlement day lease owner is required';
  END IF;
  IF p_lease_seconds < 1 THEN
    RAISE EXCEPTION 'Settlement day lease must be positive';
  END IF;
  stale_before := CURRENT_TIMESTAMP - make_interval(secs => p_lease_seconds);

  INSERT INTO daily_settlement_runs (game_day, status, current_phase, attempt_count)
  VALUES (p_game_day, 'pending', 'prepare', 0)
  ON CONFLICT (game_day) DO NOTHING;

  SELECT * INTO current_run
  FROM daily_settlement_runs
  WHERE game_day = p_game_day
  FOR UPDATE;

  IF current_run.status IN ('completed', 'baseline') THEN
    claimed := FALSE; status := current_run.status; attempt_count := current_run.attempt_count; current_phase := current_run.current_phase;
    RETURN NEXT; RETURN;
  END IF;
  IF current_run.status = 'paused' THEN
    claimed := FALSE; status := current_run.status; attempt_count := current_run.attempt_count; current_phase := current_run.current_phase;
    RETURN NEXT; RETURN;
  END IF;
  IF current_run.status = 'running'
     AND current_run.lease_owner = p_lease_owner
     AND COALESCE(current_run.lease_heartbeat_at, current_run.started_at) > stale_before THEN
    claimed := TRUE; status := current_run.status; attempt_count := current_run.attempt_count; current_phase := current_run.current_phase;
    RETURN NEXT; RETURN;
  END IF;
  IF current_run.status = 'running'
     AND current_run.lease_owner IS NOT NULL
     AND current_run.lease_owner <> p_lease_owner
     AND COALESCE(current_run.lease_heartbeat_at, current_run.started_at) > stale_before THEN
    claimed := FALSE; status := 'busy'; attempt_count := current_run.attempt_count; current_phase := current_run.current_phase;
    RETURN NEXT; RETURN;
  END IF;

  UPDATE daily_settlement_runs
  SET status = 'running', current_phase = COALESCE(current_run.current_phase, 'prepare'),
      attempt_count = current_run.attempt_count + 1, lease_owner = p_lease_owner,
      lease_heartbeat_at = CURRENT_TIMESTAMP, started_at = COALESCE(started_at, CURRENT_TIMESTAMP),
      completed_at = NULL, error_message = NULL, updated_at = CURRENT_TIMESTAMP
  WHERE game_day = p_game_day;
  claimed := TRUE; status := 'running'; attempt_count := current_run.attempt_count + 1; current_phase := COALESCE(current_run.current_phase, 'prepare');
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION earth_heartbeat_settlement_day(
  p_game_day BIGINT,
  p_lease_owner TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  UPDATE daily_settlement_runs
  SET lease_heartbeat_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
  WHERE game_day = $1 AND status = 'running' AND lease_owner = $2
  RETURNING TRUE;
$$;

CREATE OR REPLACE FUNCTION earth_complete_settlement_day(
  p_game_day BIGINT,
  p_lease_owner TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  UPDATE daily_settlement_runs
  SET status = 'completed', current_phase = 'completed', completed_at = CURRENT_TIMESTAMP,
      lease_owner = NULL, lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
  WHERE game_day = $1 AND status = 'running' AND lease_owner = $2
  RETURNING TRUE;
$$;

CREATE OR REPLACE FUNCTION earth_fail_settlement_day(
  p_game_day BIGINT,
  p_lease_owner TEXT,
  p_error_message TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  UPDATE daily_settlement_runs
  SET status = 'failed', current_phase = 'failed', error_message = left($3, 2000),
      lease_owner = NULL, lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
  WHERE game_day = $1 AND status = 'running' AND lease_owner = $2
  RETURNING TRUE;
$$;
