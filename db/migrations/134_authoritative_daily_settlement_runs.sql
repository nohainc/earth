-- Authoritative daily settlement coordination.
-- The real timestamp in world_state.genesis_at is the only clock input.

CREATE TABLE IF NOT EXISTS daily_settlement_runs (
  game_day BIGINT PRIMARY KEY CHECK (game_day >= 1),
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'baseline', 'paused')),
  current_phase TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  lease_owner TEXT,
  lease_heartbeat_at TIMESTAMPTZ,
  rules_version TEXT NOT NULL DEFAULT 'daily-settlement-v1',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS daily_settlement_runs_status_day_idx
  ON daily_settlement_runs (status, game_day);

CREATE TABLE IF NOT EXISTS daily_settlement_control (
  id TEXT PRIMARY KEY DEFAULT 'WORLD' CHECK (id = 'WORLD'),
  status TEXT NOT NULL CHECK (status IN ('awaiting_baseline', 'active', 'paused')) DEFAULT 'awaiting_baseline',
  activated_at TIMESTAMPTZ,
  activated_by TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO daily_settlement_control (id, status)
VALUES ('WORLD', 'awaiting_baseline')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS daily_settlement_phase_runs (
  game_day BIGINT NOT NULL REFERENCES daily_settlement_runs(game_day) ON DELETE CASCADE,
  phase TEXT NOT NULL,
  shard TEXT NOT NULL DEFAULT 'all',
  status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  attempt_count INTEGER NOT NULL DEFAULT 0,
  rows_processed BIGINT NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  PRIMARY KEY (game_day, phase, shard)
);

CREATE TABLE IF NOT EXISTS entity_end_of_day_snapshots (
  owner_id TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  owner_kind TEXT NOT NULL,
  credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  resources JSONB NOT NULL DEFAULT '{}'::jsonb,
  cumulative_metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
  rules_version TEXT NOT NULL DEFAULT 'daily-settlement-v1',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, game_day)
);
CREATE INDEX IF NOT EXISTS entity_eod_snapshot_day_idx
  ON entity_end_of_day_snapshots (game_day DESC, owner_kind);

CREATE TABLE IF NOT EXISTS scheduled_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id TEXT,
  action_type TEXT NOT NULL,
  due_game_day BIGINT NOT NULL CHECK (due_game_day >= 1),
  due_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (due_game_minute BETWEEN 0 AND 1439),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  correlation_id TEXT NOT NULL UNIQUE,
  claimed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS scheduled_actions_due_idx
  ON scheduled_actions (status, due_game_day, due_game_minute);

CREATE TABLE IF NOT EXISTS settlement_anomalies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_day BIGINT,
  severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'error', 'critical')),
  anomaly_type TEXT NOT NULL,
  owner_id TEXT,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS settlement_anomalies_open_idx
  ON settlement_anomalies (severity, created_at DESC) WHERE resolved_at IS NULL;

-- Do not let the legacy simulated offset create a second timeline.
CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (total_game_minutes BIGINT, genesis_at TIMESTAMPTZ, elapsed_real_seconds NUMERIC)
LANGUAGE sql STABLE AS $$
  SELECT
    FLOOR(GREATEST(0, EXTRACT(EPOCH FROM (NOW() - COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::timestamptz)))))::BIGINT,
    COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::timestamptz),
    GREATEST(0, EXTRACT(EPOCH FROM (NOW() - COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::timestamptz))))
  FROM world_state w
  WHERE w.id = 'WORLD'
  UNION ALL
  SELECT 0::BIGINT, '2026-01-01T00:00:00Z'::timestamptz, 0::NUMERIC
  WHERE NOT EXISTS (SELECT 1 FROM world_state WHERE id = 'WORLD');
$$;

-- Activation is intentionally separate from migration. An operator must create
-- one explicit baseline row after confirming the chosen cut-over day; this
-- prevents an installation from silently skipping unknown historical days.
