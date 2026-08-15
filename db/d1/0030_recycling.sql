CREATE TABLE IF NOT EXISTS recycling_events (
  id TEXT PRIMARY KEY,
  machine_id TEXT NOT NULL REFERENCES machines(id),
  owner_id TEXT NOT NULL REFERENCES humans(id),
  material_returned NUMERIC NOT NULL DEFAULT 0,
  components_returned NUMERIC NOT NULL DEFAULT 0,
  efficiency NUMERIC NOT NULL,
  game_day INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS recycling_events_owner_idx
  ON recycling_events(owner_id, game_day DESC);
