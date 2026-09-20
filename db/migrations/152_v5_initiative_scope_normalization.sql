-- EARTH ACTIVE MIGRATION: Initiative authority is Earth or Corporation only.
-- Physical placement/capacity metadata is stored separately from governance scope.

ALTER TABLE v5_initiatives
  ADD COLUMN IF NOT EXISTS physical_target JSONB
  CHECK (physical_target IS NULL OR jsonb_typeof(physical_target) = 'object');

COMMENT ON COLUMN v5_initiatives.scope_type IS
  'Governance authority only: EARTH or CORPORATION. Physical location is physical_target.';
COMMENT ON COLUMN v5_initiatives.scope_id IS
  'Corporation id when scope_type is CORPORATION; NULL for EARTH.';
COMMENT ON COLUMN v5_initiatives.physical_target IS
  'Optional physical/capacity metadata. It does not grant governance or beneficiary authority.';
