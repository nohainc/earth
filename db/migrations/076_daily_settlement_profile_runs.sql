-- Immutable per-owner/day profile snapshots. They provide replay protection
-- and a shadow audit trail before profile settlement becomes authoritative.
CREATE TABLE daily_settlement_profile_runs (
  owner_id TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  profile_version BIGINT NOT NULL,
  last_settled_game_day BIGINT NOT NULL,
  elapsed_days BIGINT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('shadow', 'applied')),
  expected_delta JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, game_day)
);
CREATE INDEX daily_settlement_profile_runs_day_idx
  ON daily_settlement_profile_runs (game_day DESC, mode);
