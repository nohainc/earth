CREATE TABLE IF NOT EXISTS business_assets (
  business_id TEXT NOT NULL REFERENCES businesses(id),
  machine_id TEXT PRIMARY KEY REFERENCES machines(id),
  assigned_game_day INTEGER NOT NULL,
  assigned_by TEXT NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id)
);

INSERT OR IGNORE INTO business_assets (business_id, machine_id, assigned_game_day, assigned_by)
SELECT businesses.id, machines.id, COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 0), 'system-backfill'
FROM machines JOIN businesses ON businesses.owner_id = machines.owner_id AND businesses.status = 'active';
