CREATE TABLE IF NOT EXISTS production_events (
  id TEXT PRIMARY KEY,
  machine_id TEXT NOT NULL REFERENCES machines(id),
  owner_id TEXT NOT NULL REFERENCES humans(id),
  resource TEXT NOT NULL CHECK (resource IN ('material','components','energy','compute')),
  amount NUMERIC NOT NULL CHECK (amount > 0),
  game_day INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS production_events_owner_idx ON production_events(owner_id, game_day DESC);
