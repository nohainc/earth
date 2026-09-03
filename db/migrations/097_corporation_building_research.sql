-- Corporation-owned building research and catalog unlocks.

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS research_project_id TEXT;

CREATE TABLE IF NOT EXISTS corporation_building_research_projects (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  building_type TEXT NOT NULL,
  catalog_id TEXT NOT NULL REFERENCES building_catalog(id),
  target_tier INTEGER NOT NULL CHECK (target_tier >= 2),
  research_cost_credits NUMERIC(18,2) NOT NULL CHECK (research_cost_credits > 0),
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
  progress NUMERIC(6,3) NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed','cancelled')),
  started_game_day BIGINT NOT NULL,
  started_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (started_game_minute BETWEEN 0 AND 1439),
  completed_game_day BIGINT,
  completed_game_minute INTEGER,
  correlation_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS corporation_building_research_corp_idx
  ON corporation_building_research_projects(corporation_id, status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS corporation_building_research_active_target_idx
  ON corporation_building_research_projects(corporation_id, catalog_id)
  WHERE status IN ('active','paused','completed');

CREATE TABLE IF NOT EXISTS corporation_building_unlocks (
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  catalog_id TEXT NOT NULL REFERENCES building_catalog(id),
  research_project_id TEXT REFERENCES corporation_building_research_projects(id),
  status TEXT NOT NULL DEFAULT 'unlocked' CHECK (status IN ('unlocked','revoked')),
  unlocked_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (corporation_id, catalog_id)
);
CREATE INDEX IF NOT EXISTS corporation_building_unlocks_catalog_idx
  ON corporation_building_unlocks(catalog_id, status);
