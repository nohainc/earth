-- Technology & Research V2 Plan 3: additive modifier families and caps.

CREATE TABLE IF NOT EXISTS technology_modifier_rules (
  family_code TEXT PRIMARY KEY,
  effect_type TEXT NOT NULL UNIQUE,
  stacking_mode TEXT NOT NULL DEFAULT 'ADDITIVE_BPS'
    CHECK (stacking_mode = 'ADDITIVE_BPS'),
  minimum_bps INTEGER NOT NULL,
  maximum_bps INTEGER NOT NULL,
  effective_from_game_day BIGINT NOT NULL DEFAULT 0 CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  definition_version INTEGER NOT NULL DEFAULT 1 CHECK (definition_version > 0),
  CHECK (minimum_bps <= maximum_bps),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

INSERT INTO technology_modifier_rules (family_code, effect_type, minimum_bps, maximum_bps)
VALUES
  ('PRODUCTION_OUTPUT', 'PRODUCTION_OUTPUT', 0, 3000),
  ('RESOURCE_INPUT', 'RESOURCE_INPUT', -3000, 3000),
  ('CONSTRUCTION_TIME', 'CONSTRUCTION_TIME', -3000, 3000),
  ('CONSTRUCTION_RESOURCE_COST', 'CONSTRUCTION_RESOURCE_COST', -3000, 3000),
  ('BUILDING_WEAR', 'BUILDING_WEAR', -4000, 0),
  ('REPAIR_EFFICIENCY', 'REPAIR_EFFICIENCY', 0, 4000),
  ('RESEARCH_CAPACITY', 'RESEARCH_CAPACITY', 0, 2500),
  ('SERVICE_CAPACITY', 'SERVICE_CAPACITY', 0, 3000),
  ('ENERGY_INPUT', 'ENERGY_INPUT', -3000, 3000)
ON CONFLICT (family_code) DO NOTHING;

ALTER TABLE technology_effects ADD COLUMN IF NOT EXISTS modifier_family TEXT;
UPDATE technology_effects
SET modifier_family = effect_type
WHERE modifier_family IS NULL;
ALTER TABLE technology_effects ALTER COLUMN modifier_family SET NOT NULL;
ALTER TABLE technology_effects DROP CONSTRAINT IF EXISTS technology_effects_modifier_family_fk;
ALTER TABLE technology_effects ADD CONSTRAINT technology_effects_modifier_family_fk
  FOREIGN KEY (modifier_family) REFERENCES technology_modifier_rules(family_code);
CREATE INDEX IF NOT EXISTS technology_effects_family_idx
  ON technology_effects (modifier_family, target_type, target_key, technology_id);

CREATE OR REPLACE FUNCTION earth_resolve_technology_modifiers(
  p_technology_ids TEXT[], p_game_day BIGINT
)
RETURNS TABLE (
  modifier_family TEXT,
  effect_type TEXT,
  target_type TEXT,
  target_key TEXT,
  modifier_bps INTEGER,
  stacking_mode TEXT
)
LANGUAGE SQL
STABLE
AS $$
  SELECT r.family_code, r.effect_type, e.target_type, e.target_key,
    LEAST(r.maximum_bps, GREATEST(r.minimum_bps, SUM(e.modifier_bps)::INTEGER)) AS modifier_bps,
    r.stacking_mode
  FROM technology_effects e
  JOIN technology_modifier_rules r ON r.family_code = e.modifier_family
  JOIN technology_catalog t ON t.id = e.technology_id
  WHERE e.technology_id = ANY(p_technology_ids)
    AND t.effective_from_game_day <= p_game_day
    AND (t.effective_to_game_day IS NULL OR t.effective_to_game_day >= p_game_day)
    AND t.status = 'ACTIVE'
    AND r.effective_from_game_day <= p_game_day
    AND (r.effective_to_game_day IS NULL OR r.effective_to_game_day >= p_game_day)
  GROUP BY r.family_code, r.effect_type, e.target_type, e.target_key, r.minimum_bps, r.maximum_bps, r.stacking_mode
  ORDER BY r.family_code, e.target_type, e.target_key;
$$;

COMMENT ON TABLE technology_modifier_rules IS
  'Technology modifier families use additive BPS stacking with explicit game-day-effective caps.';
