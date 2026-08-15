CREATE TABLE IF NOT EXISTS machine_acquisitions (
  id TEXT PRIMARY KEY,
  machine_id TEXT NOT NULL REFERENCES machines(id),
  owner_id TEXT NOT NULL REFERENCES humans(id),
  machine_type TEXT NOT NULL,
  credit_cost NUMERIC NOT NULL,
  material_cost NUMERIC NOT NULL,
  game_day INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS machine_acquisitions_owner_idx ON machine_acquisitions(owner_id, game_day DESC);
