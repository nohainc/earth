-- Building Economy V2 Plan 19: canonical fixed-point settlement values.
--
-- The decimal source columns remain temporarily so the preceding migration
-- functions can be retired independently. These generated columns are the
-- canonical values consumed by posting, journals, and future planners.

CREATE OR REPLACE FUNCTION earth_ratio_to_ppm(p_value NUMERIC)
RETURNS BIGINT
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
  SELECT LEAST(1000000::BIGINT, GREATEST(0::BIGINT, ROUND(p_value * 1000000)::BIGINT));
$$;

CREATE OR REPLACE FUNCTION earth_condition_to_bp(p_value NUMERIC)
RETURNS BIGINT
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
  SELECT LEAST(10000::BIGINT, GREATEST(0::BIGINT, ROUND(p_value * 100)::BIGINT));
$$;

CREATE OR REPLACE FUNCTION earth_multiplier_to_ppm(p_value NUMERIC)
RETURNS BIGINT
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
  SELECT GREATEST(0::BIGINT, ROUND(p_value * 1000000)::BIGINT);
$$;

CREATE OR REPLACE FUNCTION earth_fixed_point_multiply_ppm(p_left BIGINT, p_right BIGINT)
RETURNS BIGINT
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
  SELECT ROUND((p_left::NUMERIC * p_right::NUMERIC) / 1000000)::BIGINT;
$$;

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS utilization_ppm BIGINT
    GENERATED ALWAYS AS (earth_ratio_to_ppm(utilization)) STORED,
  ADD COLUMN IF NOT EXISTS condition_efficiency_ppm BIGINT
    GENERATED ALWAYS AS (earth_ratio_to_ppm(condition_efficiency)) STORED,
  ADD COLUMN IF NOT EXISTS condition_before_bp BIGINT
    GENERATED ALWAYS AS (earth_condition_to_bp(condition_before)) STORED,
  ADD COLUMN IF NOT EXISTS condition_after_bp BIGINT
    GENERATED ALWAYS AS (earth_condition_to_bp(condition_after)) STORED,
  ADD COLUMN IF NOT EXISTS wear_points_bp BIGINT
    GENERATED ALWAYS AS (earth_condition_to_bp(wear)) STORED,
  ADD COLUMN IF NOT EXISTS repair_points_bp BIGINT
    GENERATED ALWAYS AS (earth_condition_to_bp(repair_points)) STORED,
  ADD COLUMN IF NOT EXISTS maintenance_fulfillment_ppm BIGINT
    GENERATED ALWAYS AS (earth_ratio_to_ppm(maintenance_fulfillment)) STORED,
  ADD COLUMN IF NOT EXISTS repair_target_condition_bp BIGINT
    GENERATED ALWAYS AS (earth_condition_to_bp(repair_target_condition)) STORED;

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS base_condition_decay_ppm BIGINT
    GENERATED ALWAYS AS (earth_multiplier_to_ppm(base_condition_decay)) STORED,
  ADD COLUMN IF NOT EXISTS maintenance_wear_multiplier_ppm BIGINT
    GENERATED ALWAYS AS (earth_multiplier_to_ppm(maintenance_wear_multiplier)) STORED,
  ADD COLUMN IF NOT EXISTS repair_materials_per_point_ppm BIGINT
    GENERATED ALWAYS AS (ROUND(repair_materials_per_point * 1000000)::BIGINT) STORED,
  ADD COLUMN IF NOT EXISTS repair_components_per_point_ppm BIGINT
    GENERATED ALWAYS AS (ROUND(repair_components_per_point * 1000000)::BIGINT) STORED;

ALTER TABLE building_settlement_plans
  ADD CONSTRAINT building_settlement_plans_fixed_point_bounds_ck CHECK (
    utilization_ppm BETWEEN 0 AND 1000000
    AND condition_efficiency_ppm BETWEEN 0 AND 1000000
    AND condition_before_bp BETWEEN 0 AND 10000
    AND condition_after_bp BETWEEN 0 AND 10000
    AND maintenance_fulfillment_ppm BETWEEN 0 AND 1000000
  );

COMMENT ON COLUMN building_settlement_plans.utilization_ppm IS
  'Canonical fixed-point utilization ratio; one million means 100 percent.';
COMMENT ON COLUMN building_settlement_plans.condition_efficiency_ppm IS
  'Canonical fixed-point condition efficiency ratio.';
COMMENT ON COLUMN building_settlement_plans.condition_before_bp IS
  'Canonical condition in basis points; 10000 means condition 100.';
COMMENT ON COLUMN building_settlement_plans.condition_after_bp IS
  'Canonical condition in basis points; 10000 means condition 100.';
COMMENT ON TABLE building_settlement_plans IS
  'Building settlement staging. Decimal compatibility inputs are retained temporarily; generated fixed-point columns are authoritative for V2 posting and audit.';
