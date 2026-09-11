-- Technology & Research V2 Plan 15: freeze construction technology terms at start.

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS construction_rules_version TEXT,
  ADD COLUMN IF NOT EXISTS construction_technology_modifiers JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS construction_base_duration_minutes BIGINT,
  ADD COLUMN IF NOT EXISTS construction_duration_minutes BIGINT,
  ADD COLUMN IF NOT EXISTS construction_cost_credits_units BIGINT,
  ADD COLUMN IF NOT EXISTS construction_cost_material_units BIGINT,
  ADD COLUMN IF NOT EXISTS construction_cost_components_units BIGINT,
  ADD COLUMN IF NOT EXISTS construction_cost_compute_units BIGINT;

ALTER TABLE buildings
  ADD CONSTRAINT buildings_construction_snapshot_nonnegative_ck CHECK (
    construction_base_duration_minutes IS NULL OR construction_base_duration_minutes >= 0
  ),
  ADD CONSTRAINT buildings_construction_duration_snapshot_nonnegative_ck CHECK (
    construction_duration_minutes IS NULL OR construction_duration_minutes >= 0
  ),
  ADD CONSTRAINT buildings_construction_cost_snapshot_nonnegative_ck CHECK (
    COALESCE(construction_cost_credits_units, 0) >= 0
    AND COALESCE(construction_cost_material_units, 0) >= 0
    AND COALESCE(construction_cost_components_units, 0) >= 0
    AND COALESCE(construction_cost_compute_units, 0) >= 0
  );

COMMENT ON COLUMN buildings.construction_technology_modifiers IS
  'Immutable technology modifier set captured when construction starts.';
COMMENT ON COLUMN buildings.construction_duration_minutes IS
  'Authoritative construction duration captured at start; later technology changes cannot alter completion.';
