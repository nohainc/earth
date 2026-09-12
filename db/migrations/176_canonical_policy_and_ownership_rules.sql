-- Economy V2: canonical policy and ownership codes.

CREATE TABLE IF NOT EXISTS economic_policy_rules (
  code TEXT PRIMARY KEY,
  output_multiplier NUMERIC(8,4) NOT NULL CHECK (output_multiplier >= 0),
  cost_multiplier NUMERIC(8,4) NOT NULL CHECK (cost_multiplier >= 0),
  decay_multiplier NUMERIC(8,4) NOT NULL CHECK (decay_multiplier >= 0),
  is_selectable BOOLEAN NOT NULL DEFAULT TRUE,
  description TEXT NOT NULL
);

INSERT INTO economic_policy_rules (code, output_multiplier, cost_multiplier, decay_multiplier, description) VALUES
  ('balanced', 1.00, 1.00, 1.00, 'Normal production and operating costs'),
  ('high_output', 1.30, 1.40, 1.75, 'Higher output with higher operating cost and wear'),
  ('eco_reserve', 0.75, 0.70, 0.50, 'Reduced output and costs with lower wear'),
  ('halted', 0.00, 0.20, 0.10, 'Production halted with minimum operating cost and low residual wear'),
  ('overclock', 1.60, 1.90, 3.00, 'Extreme output with extreme operating cost and wear')
ON CONFLICT (code) DO UPDATE SET
  output_multiplier = EXCLUDED.output_multiplier,
  cost_multiplier = EXCLUDED.cost_multiplier,
  decay_multiplier = EXCLUDED.decay_multiplier,
  description = EXCLUDED.description;

CREATE TABLE IF NOT EXISTS economic_ownership_classes (
  code TEXT PRIMARY KEY,
  owner_scope TEXT NOT NULL CHECK (owner_scope IN ('human', 'city')),
  profile_scope TEXT NOT NULL CHECK (profile_scope IN ('private', 'civic')),
  description TEXT NOT NULL
);

INSERT INTO economic_ownership_classes (code, owner_scope, profile_scope, description) VALUES
  ('private', 'human', 'private', 'Human-owned economic activity'),
  ('civic', 'city', 'civic', 'City-owned civic economic activity')
ON CONFLICT (code) DO UPDATE SET
  owner_scope = EXCLUDED.owner_scope,
  profile_scope = EXCLUDED.profile_scope,
  description = EXCLUDED.description;

ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_operating_policy_check;
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_operating_policy_fkey;
ALTER TABLE buildings
  ADD CONSTRAINT buildings_operating_policy_fkey
  FOREIGN KEY (operating_policy) REFERENCES economic_policy_rules(code);

ALTER TABLE building_catalog DROP CONSTRAINT IF EXISTS building_catalog_ownership_class_fkey;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_ownership_class_fkey
  FOREIGN KEY (ownership_class) REFERENCES economic_ownership_classes(code);

ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_ownership_class_check;
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_ownership_class_fkey;
ALTER TABLE buildings
  ADD CONSTRAINT buildings_ownership_class_fkey
  FOREIGN KEY (ownership_class) REFERENCES economic_ownership_classes(code);

-- Make the canonical calculator consume rule data rather than embedding policy
-- multipliers in SQL branches.
CREATE OR REPLACE FUNCTION earth_calculate_building_economics(p_building_id TEXT)
RETURNS TABLE (
  asset_id SMALLINT,
  asset_code TEXT,
  output_units NUMERIC,
  upkeep_units NUMERIC,
  operating_units NUMERIC,
  effective_output_multiplier NUMERIC,
  effective_cost_multiplier NUMERIC
)
LANGUAGE SQL
STABLE
AS $$
  SELECT v.asset_id,
         v.asset_code,
         v.output_units,
         v.upkeep_units,
         v.operating_units,
         policy.output_multiplier,
         policy.cost_multiplier
  FROM buildings b
  JOIN building_catalog bc
    ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  JOIN economic_policy_rules policy ON policy.code = b.operating_policy
  CROSS JOIN LATERAL (VALUES
    (1::SMALLINT, 'CREDIT'::TEXT,     0,                                    COALESCE(bc.upkeep_credits, 0),     COALESCE(bc.operating_credits, 0)),
    (2::SMALLINT, 'MATERIAL'::TEXT,   COALESCE(bc.output_materials, 0),   COALESCE(bc.upkeep_materials, 0),   COALESCE(bc.operating_materials, 0)),
    (3::SMALLINT, 'COMPONENTS'::TEXT, COALESCE(bc.output_components, 0),  COALESCE(bc.upkeep_components, 0),  COALESCE(bc.operating_components, 0)),
    (4::SMALLINT, 'ENERGY'::TEXT,     COALESCE(bc.output_energy, 0),     COALESCE(bc.upkeep_energy, 0),     COALESCE(bc.operating_energy, 0)),
    (5::SMALLINT, 'COMPUTE'::TEXT,    COALESCE(bc.output_compute, 0),    COALESCE(bc.upkeep_compute, 0),    COALESCE(bc.operating_compute, 0)),
    (6::SMALLINT, 'FOOD'::TEXT,       COALESCE(bc.output_food, 0),       COALESCE(bc.upkeep_food, 0),       COALESCE(bc.operating_food, 0))
  ) AS v(asset_id, asset_code, output_units, upkeep_units, operating_units)
  WHERE b.id = p_building_id;
$$;
