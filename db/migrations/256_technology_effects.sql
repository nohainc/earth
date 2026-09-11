-- Technology & Research V2 Plan 2: normalized, machine-readable effects.

CREATE TABLE IF NOT EXISTS technology_effects (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id) ON DELETE CASCADE,
  effect_type TEXT NOT NULL CHECK (effect_type IN (
    'PRODUCTION_OUTPUT', 'RESOURCE_INPUT', 'CONSTRUCTION_TIME',
    'CONSTRUCTION_RESOURCE_COST', 'BUILDING_WEAR', 'REPAIR_EFFICIENCY',
    'RESEARCH_CAPACITY', 'SERVICE_CAPACITY', 'ENERGY_INPUT'
  )),
  target_type TEXT NOT NULL CHECK (target_type IN ('ALL_BUILDINGS', 'ASSET', 'BUILDING', 'SERVICE', 'RESEARCH')),
  target_key TEXT NOT NULL,
  modifier_bps INTEGER NOT NULL CHECK (modifier_bps BETWEEN -100000 AND 100000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (technology_id, effect_type, target_type, target_key)
);

CREATE INDEX IF NOT EXISTS technology_effects_target_idx
  ON technology_effects (effect_type, target_type, target_key, technology_id);

INSERT INTO technology_effects (technology_id, effect_type, target_type, target_key, modifier_bps)
VALUES
  ('TECH-AUTOMATED-ASSEMBLY-V1', 'PRODUCTION_OUTPUT', 'ASSET', 'COMPONENTS', 1000),
  ('TECH-CLEAN-ENERGY-SYSTEMS-V1', 'ENERGY_INPUT', 'ALL_BUILDINGS', 'ALL', -1000),
  ('TECH-FOOD-SYNTHESIS-V1', 'PRODUCTION_OUTPUT', 'ASSET', 'FOOD', 1000),
  ('TECH-PREDICTIVE-MAINTENANCE-V1', 'BUILDING_WEAR', 'ALL_BUILDINGS', 'ALL', -1000),
  ('TECH-CIVIC-NETWORK-INFRASTRUCTURE-V1', 'SERVICE_CAPACITY', 'SERVICE', 'ALL', 1000)
ON CONFLICT (technology_id, effect_type, target_type, target_key) DO NOTHING;

COMMENT ON TABLE technology_effects IS
  'Normalized Technology V2 modifiers. Effects are basis-point data consumed by economic calculators.';
