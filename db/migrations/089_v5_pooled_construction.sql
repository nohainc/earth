-- EARTH ACTIVE MIGRATION: V5 construction no longer requires a Territory
-- placement target. Legacy location/right columns remain for historical rows.

ALTER TABLE buildings ALTER COLUMN territory_id DROP NOT NULL;
ALTER TABLE construction_projects ALTER COLUMN territory_id DROP NOT NULL;
ALTER TABLE construction_projects DROP CONSTRAINT IF EXISTS construction_projects_project_kind_check;
ALTER TABLE construction_projects ADD CONSTRAINT construction_projects_project_kind_check
  CHECK (project_kind IN ('NEW_BUILDING','OVERHAUL','GENERATION_RETROFIT','TIER_UPGRADE','V5_POOLED_CONSTRUCTION'));
