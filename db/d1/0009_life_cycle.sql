ALTER TABLE humans ADD COLUMN life_status TEXT NOT NULL DEFAULT 'active' CHECK (life_status IN ('active','deceased','estate'));
ALTER TABLE humans ADD COLUMN death_game_day INTEGER;

CREATE TABLE IF NOT EXISTS life_events (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('birth','death','inheritance')),
  game_day INTEGER NOT NULL,
  successor_name TEXT,
  estate_credits NUMERIC NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS life_events_human_idx ON life_events(human_id, game_day DESC);
