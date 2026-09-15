-- EARTH ACTIVE MIGRATION: building investment actions and operating modes

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS operating_mode TEXT NOT NULL DEFAULT 'BALANCED'
    CHECK (operating_mode IN ('CONSERVATIVE', 'BALANCED', 'GROWTH'));

ALTER TABLE construction_projects
  DROP CONSTRAINT IF EXISTS construction_projects_project_kind_check;
ALTER TABLE construction_projects
  ADD CONSTRAINT construction_projects_project_kind_check
    CHECK (project_kind IN ('NEW_BUILDING', 'OVERHAUL', 'GENERATION_RETROFIT', 'TIER_UPGRADE'));

CREATE INDEX IF NOT EXISTS buildings_operating_mode_idx
  ON buildings (owner_economic_id, operating_mode, status);
