CREATE TABLE IF NOT EXISTS membership_events (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  institution_type TEXT NOT NULL,
  institution_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('joined','left','released')),
  game_day INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS membership_events_human_idx ON membership_events(human_id, game_day DESC);
CREATE INDEX IF NOT EXISTS membership_events_institution_idx ON membership_events(institution_id, game_day DESC);
