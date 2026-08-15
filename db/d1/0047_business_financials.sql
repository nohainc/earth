CREATE TABLE IF NOT EXISTS business_financials (
  business_id TEXT PRIMARY KEY REFERENCES businesses(id),
  revenue NUMERIC NOT NULL DEFAULT 0 CHECK (revenue >= 0),
  operating_costs NUMERIC NOT NULL DEFAULT 0 CHECK (operating_costs >= 0),
  profit NUMERIC NOT NULL DEFAULT 0,
  last_game_day INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO business_financials (business_id, last_game_day)
SELECT id, COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 0)
FROM businesses;
