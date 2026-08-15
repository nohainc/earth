CREATE TABLE IF NOT EXISTS machine_upgrade_events (
  id TEXT PRIMARY KEY,
  machine_id TEXT NOT NULL REFERENCES machines(id),
  owner_id TEXT NOT NULL REFERENCES humans(id),
  credit_cost NUMERIC NOT NULL,
  components_cost NUMERIC NOT NULL,
  capacity_before NUMERIC NOT NULL,
  capacity_after NUMERIC NOT NULL,
  game_day INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS machine_upgrade_events_owner_idx
  ON machine_upgrade_events(owner_id, game_day DESC);
