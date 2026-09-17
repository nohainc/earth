-- EARTH ACTIVE MIGRATION: persist the authority source of each resolved rule.

ALTER TABLE resolved_constitution_snapshots_v5
  ADD COLUMN IF NOT EXISTS provenance_json JSONB NOT NULL DEFAULT '{}'::JSONB
  CHECK (jsonb_typeof(provenance_json) = 'object');
