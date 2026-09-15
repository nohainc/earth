-- EARTH ACTIVE MIGRATION: derived building age, design life, and generation installs

CREATE TABLE IF NOT EXISTS building_design_life_rules (
  catalog_id TEXT PRIMARY KEY REFERENCES building_catalog(id),
  design_life_days BIGINT NOT NULL CHECK (design_life_days > 0),
  overdue_burden_bps_per_day INTEGER NOT NULL CHECK (overdue_burden_bps_per_day >= 0),
  maximum_burden_bps INTEGER NOT NULL CHECK (maximum_burden_bps >= 10000),
  rules_version TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS building_generation_installations (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id),
  domain_id TEXT NOT NULL REFERENCES technology_domains(id),
  generation_id TEXT NOT NULL REFERENCES technology_generations(id),
  installed_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REMOVED')),
  correlation_id TEXT NOT NULL UNIQUE,
  UNIQUE (building_id, domain_id, status)
);
ALTER TABLE construction_projects ADD COLUMN IF NOT EXISTS project_kind TEXT NOT NULL DEFAULT 'NEW_BUILDING' CHECK (project_kind IN ('NEW_BUILDING','OVERHAUL','GENERATION_RETROFIT'));
ALTER TABLE construction_projects ADD COLUMN IF NOT EXISTS target_generation_id TEXT REFERENCES technology_generations(id);
CREATE INDEX IF NOT EXISTS building_generation_installations_building_idx ON building_generation_installations (building_id, status, installed_game_day DESC);

INSERT INTO building_design_life_rules (catalog_id, design_life_days, overdue_burden_bps_per_day, maximum_burden_bps, rules_version)
SELECT id, 3650, 2, 15000, 'building-life-v1' FROM building_catalog
ON CONFLICT (catalog_id) DO NOTHING;
