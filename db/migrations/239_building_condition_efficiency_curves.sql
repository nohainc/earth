-- Building Economy V2 Plan 6: versioned condition-to-efficiency curves.

CREATE TABLE IF NOT EXISTS building_condition_efficiency_curves (
  curve_version TEXT NOT NULL,
  condition_value NUMERIC(10,4) NOT NULL CHECK (condition_value BETWEEN 0 AND 100),
  efficiency NUMERIC(12,8) NOT NULL CHECK (efficiency BETWEEN 0 AND 1),
  PRIMARY KEY (curve_version, condition_value)
);

INSERT INTO building_condition_efficiency_curves (curve_version, condition_value, efficiency) VALUES
  ('v1', 0, 0.00),
  ('v1', 20, 0.40),
  ('v1', 40, 0.60),
  ('v1', 60, 0.75),
  ('v1', 80, 0.90),
  ('v1', 100, 1.00)
ON CONFLICT (curve_version, condition_value) DO NOTHING;

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS condition_curve_version TEXT NOT NULL DEFAULT 'v1';
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS condition_curve_version TEXT NOT NULL DEFAULT 'v1';

CREATE OR REPLACE FUNCTION earth_condition_efficiency(
  p_condition NUMERIC,
  p_curve_version TEXT DEFAULT 'v1'
)
RETURNS NUMERIC
LANGUAGE SQL
STABLE
AS $$
  WITH bounds AS (
    SELECT
      (SELECT c.condition_value FROM building_condition_efficiency_curves c
       WHERE curve_version = p_curve_version AND condition_value <= GREATEST(0, LEAST(100, p_condition))
       ORDER BY condition_value DESC LIMIT 1) AS lower_condition,
      (SELECT c.efficiency FROM building_condition_efficiency_curves c
       WHERE curve_version = p_curve_version AND condition_value <= GREATEST(0, LEAST(100, p_condition))
       ORDER BY condition_value DESC LIMIT 1) AS lower_efficiency,
      (SELECT c.condition_value FROM building_condition_efficiency_curves c
       WHERE curve_version = p_curve_version AND condition_value >= GREATEST(0, LEAST(100, p_condition))
       ORDER BY condition_value ASC LIMIT 1) AS upper_condition,
      (SELECT c.efficiency FROM building_condition_efficiency_curves c
       WHERE curve_version = p_curve_version AND condition_value >= GREATEST(0, LEAST(100, p_condition))
       ORDER BY condition_value ASC LIMIT 1) AS upper_efficiency
  )
  SELECT CASE
    WHEN lower_condition IS NULL THEN upper_efficiency
    WHEN upper_condition IS NULL THEN lower_efficiency
    WHEN lower_condition = upper_condition THEN lower_efficiency
    ELSE lower_efficiency
      + (upper_efficiency - lower_efficiency)
        * (GREATEST(0, LEAST(100, p_condition)) - lower_condition)
        / (upper_condition - lower_condition)
  END
  FROM bounds;
$$;

CREATE OR REPLACE FUNCTION earth_apply_building_condition_efficiency(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building condition efficiency day or shard';
  END IF;

  UPDATE building_settlement_plans p
  SET condition_curve_version = COALESCE(c.condition_curve_version, 'v1'),
      condition_efficiency = earth_condition_efficiency(
        p.condition_before, COALESCE(c.condition_curve_version, 'v1')
      )
  FROM buildings b
  LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  WHERE p.building_id = b.id AND p.game_day = p_game_day AND p.shard = p_shard;

  WITH changed AS (
    UPDATE building_settlement_plans p
    SET production = COALESCE(production_values.values, '{}'::JSONB),
        service_capacity = ROUND(p.service_capacity * p.condition_efficiency)::BIGINT
    FROM LATERAL (
      SELECT jsonb_object_agg(k, to_jsonb(ROUND((v::NUMERIC) * p.condition_efficiency, 6))) AS values
      FROM jsonb_each_text(p.production) outputs(k, v)
      WHERE (v::NUMERIC) > 0
    ) production_values
    WHERE p.game_day = p_game_day AND p.shard = p_shard
    RETURNING p.building_id
  )
  SELECT COUNT(*) INTO v_count FROM changed;
  RETURN v_count;
END;
$$;

CREATE INDEX IF NOT EXISTS building_condition_efficiency_curves_version_idx
  ON building_condition_efficiency_curves (curve_version, condition_value);
