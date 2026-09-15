-- EARTH ACTIVE MIGRATION: Territory geography is no longer owned by a Corporation

ALTER TABLE territories
  ALTER COLUMN corporation_id DROP NOT NULL;

COMMENT ON COLUMN territories.corporation_id IS
  'Legacy Corporation compatibility pointer; active Territory governance is assigned through territory_governance.';
