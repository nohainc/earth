-- Death & Continuity V2 Plan 24.
-- One durable audit identity for every generational transition.

CREATE TABLE IF NOT EXISTS succession_events (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  predecessor_human_id TEXT NOT NULL REFERENCES humans(id),
  successor_human_id TEXT NOT NULL REFERENCES humans(id),
  death_game_day BIGINT NOT NULL,
  effective_game_day BIGINT NOT NULL,
  reason TEXT NOT NULL,
  predecessor_age INTEGER NOT NULL,
  predecessor_standing INTEGER NOT NULL,
  predecessor_legacy INTEGER NOT NULL,
  house_legacy_before BIGINT NOT NULL,
  house_legacy_after BIGINT,
  rule_version TEXT,
  status TEXT NOT NULL DEFAULT 'PREPARED' CHECK (status IN ('PREPARED', 'COMPLETED', 'FAILED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS succession_events_house_idx ON succession_events(house_id, death_game_day DESC);
CREATE INDEX IF NOT EXISTS succession_events_status_idx ON succession_events(status, effective_game_day);
