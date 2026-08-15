CREATE TABLE IF NOT EXISTS business_management (
  business_id TEXT PRIMARY KEY REFERENCES businesses(id),
  manager_id TEXT NOT NULL REFERENCES humans(id),
  appointed_by TEXT NOT NULL REFERENCES humans(id),
  appointed_game_day INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO business_management (business_id, manager_id, appointed_by, appointed_game_day)
SELECT id, owner_id, owner_id, COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 0)
FROM businesses;
