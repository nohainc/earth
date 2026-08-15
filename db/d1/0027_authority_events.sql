CREATE TABLE IF NOT EXISTS authority_events (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  institution_id TEXT NOT NULL,
  role_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('claimed','resigned','expired','released')),
  game_day INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS authority_events_human_idx ON authority_events(human_id, game_day DESC);
CREATE INDEX IF NOT EXISTS authority_events_institution_idx ON authority_events(institution_id, game_day DESC);
