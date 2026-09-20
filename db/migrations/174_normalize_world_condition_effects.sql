-- Normalize World Condition identity from its one-or-more typed effects.
ALTER TABLE world_conditions
  ADD COLUMN IF NOT EXISTS severity TEXT NOT NULL DEFAULT 'INFO',
  ADD COLUMN IF NOT EXISTS definition_version TEXT NOT NULL DEFAULT 'world-conditions-v2';

ALTER TABLE world_conditions
  ADD CONSTRAINT world_conditions_severity_check
  CHECK (severity IN ('INFO', 'WATCH', 'CRITICAL'));

CREATE TABLE IF NOT EXISTS world_condition_effects (
  id TEXT PRIMARY KEY,
  condition_id TEXT NOT NULL REFERENCES world_conditions(id) ON DELETE CASCADE,
  effect_type TEXT NOT NULL CHECK (effect_type IN ('SUPPLY_MULTIPLIER','DEMAND_MULTIPLIER','CAPACITY_MULTIPLIER','LABOR_INDEX','CONSTRUCTION_INDEX')),
  target_key TEXT NOT NULL,
  modifier_bps INTEGER NOT NULL CHECK (modifier_bps BETWEEN -5000 AND 5000),
  effect_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (condition_id, effect_type, target_key)
);

INSERT INTO world_condition_effects (id, condition_id, effect_type, target_key, modifier_bps)
SELECT 'WCE-' || wc.id, wc.id, wc.effect_type, wc.target_key, wc.modifier_bps
  FROM world_conditions wc
 ON CONFLICT (condition_id, effect_type, target_key) DO NOTHING;

ALTER TABLE world_conditions DROP CONSTRAINT IF EXISTS world_conditions_effect_type_check;
ALTER TABLE world_conditions DROP COLUMN IF EXISTS effect_type;
ALTER TABLE world_conditions DROP COLUMN IF EXISTS target_key;
ALTER TABLE world_conditions DROP COLUMN IF EXISTS modifier_bps;

CREATE INDEX IF NOT EXISTS world_condition_effects_condition_idx
  ON world_condition_effects (condition_id, effect_order, id);
CREATE INDEX IF NOT EXISTS world_condition_effects_lookup_idx
  ON world_condition_effects (effect_type, target_key, condition_id);
