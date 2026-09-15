-- EARTH ACTIVE MIGRATION: repeatable capital projects

-- A building may undergo several economic lifecycle decisions over time.
-- Preserve historical projects while allowing one active project at a time.
ALTER TABLE construction_projects
  DROP CONSTRAINT IF EXISTS construction_projects_building_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS construction_projects_active_building_uq
  ON construction_projects (building_id)
  WHERE status = 'IN_PROGRESS';
