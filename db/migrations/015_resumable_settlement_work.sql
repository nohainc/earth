-- EARTH ACTIVE MIGRATION: resumable settlement work units

CREATE TABLE IF NOT EXISTS daily_settlement_phase_runs (
  id BIGSERIAL PRIMARY KEY,
  game_day BIGINT NOT NULL REFERENCES daily_settlement_runs(game_day),
  phase_id TEXT NOT NULL,
  phase_order INTEGER NOT NULL CHECK (phase_order >= 0),
  shard INTEGER NOT NULL CHECK (shard >= 0),
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed')),
  correlation_id TEXT NOT NULL UNIQUE,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  lease_owner TEXT,
  lease_expires_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  result JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, phase_id, shard)
);

CREATE INDEX IF NOT EXISTS daily_settlement_phase_runs_claim_idx
  ON daily_settlement_phase_runs (game_day, status, lease_expires_at, phase_order, shard);
CREATE INDEX IF NOT EXISTS daily_settlement_phase_runs_failures_idx
  ON daily_settlement_phase_runs (game_day, status) WHERE status = 'failed';

CREATE OR REPLACE FUNCTION earth_claim_settlement_day(
  p_game_day BIGINT, p_worker_id TEXT, p_lease_seconds INTEGER DEFAULT 30
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  WITH candidate AS (
    SELECT current.id
      FROM daily_settlement_phase_runs current
     WHERE current.game_day = p_game_day
       AND (current.status = 'pending' OR (current.status = 'running' AND current.lease_expires_at < CURRENT_TIMESTAMP))
       AND NOT EXISTS (
         SELECT 1 FROM daily_settlement_phase_runs prior
          WHERE prior.game_day = current.game_day
            AND prior.phase_order < current.phase_order
            AND prior.status <> 'completed'
       )
     ORDER BY current.phase_order, current.shard
     FOR UPDATE SKIP LOCKED LIMIT 1
  )
  UPDATE daily_settlement_phase_runs work
     SET status = 'running', lease_owner = p_worker_id,
         lease_expires_at = CURRENT_TIMESTAMP + (p_lease_seconds::TEXT || ' seconds')::INTERVAL,
         attempt_count = work.attempt_count + 1,
         started_at = COALESCE(work.started_at, CURRENT_TIMESTAMP), updated_at = CURRENT_TIMESTAMP
    FROM candidate WHERE work.id = candidate.id
  RETURNING work.id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_heartbeat_settlement_day(
  p_game_day BIGINT, p_worker_id TEXT, p_phase_id TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_runs
     SET current_phase = p_phase_id, lease_owner = p_worker_id,
         lease_heartbeat_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running';
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_complete_settlement_day(p_game_day BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_runs
     SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
         current_phase = NULL, lease_owner = NULL,
         lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running'
     AND NOT EXISTS (
       SELECT 1 FROM daily_settlement_phase_runs
        WHERE game_day = p_game_day AND status <> 'completed'
     );
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_fail_settlement_day(
  p_work_id BIGINT, p_worker_id TEXT, p_error_message TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_phase_runs
     SET status = CASE WHEN attempt_count >= 5 THEN 'failed' ELSE 'pending' END,
         lease_owner = NULL, lease_expires_at = NULL,
         error_message = LEFT(p_error_message, 1000), updated_at = CURRENT_TIMESTAMP
   WHERE id = p_work_id AND status = 'running' AND lease_owner = p_worker_id;
  RETURN FOUND;
END;
$$;
