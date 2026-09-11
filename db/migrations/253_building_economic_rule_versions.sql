-- Building Economy V2 Plan 20: game-day-effective building rule snapshots.

CREATE TABLE IF NOT EXISTS building_economic_rule_versions (
  catalog_id TEXT NOT NULL REFERENCES building_catalog(id) ON DELETE CASCADE,
  rules_version TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  production_recipes JSONB NOT NULL DEFAULT '{}'::JSONB,
  upkeep JSONB NOT NULL DEFAULT '{}'::JSONB,
  condition_curve_version TEXT NOT NULL DEFAULT 'v1',
  condition_decay_ppm BIGINT NOT NULL DEFAULT 1000000 CHECK (condition_decay_ppm >= 0),
  repair_costs JSONB NOT NULL DEFAULT '{}'::JSONB,
  service_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (service_capacity_units >= 0),
  service_price_units BIGINT NOT NULL DEFAULT 0 CHECK (service_price_units >= 0),
  service_matching_rules JSONB NOT NULL DEFAULT '{}'::JSONB,
  operation_mode TEXT NOT NULL DEFAULT 'SCALABLE',
  minimum_operating_ratio_ppm BIGINT NOT NULL DEFAULT 0 CHECK (minimum_operating_ratio_ppm BETWEEN 0 AND 1000000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (catalog_id, rules_version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  UNIQUE (catalog_id, effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS building_economic_rule_versions_effective_idx
  ON building_economic_rule_versions (catalog_id, effective_from_game_day DESC);

INSERT INTO building_economic_rule_versions (
  catalog_id, rules_version, effective_from_game_day, production_recipes, upkeep,
  condition_curve_version, condition_decay_ppm, repair_costs,
  service_capacity_units, service_price_units, operation_mode, minimum_operating_ratio_ppm
)
SELECT c.id, 'building-catalog-v1', 0,
  jsonb_build_object(
    'ENERGY', ROUND(COALESCE(c.output_energy, 0) * 1000000)::BIGINT,
    'FOOD', ROUND(COALESCE(c.output_food, 0) * 1000000)::BIGINT,
    'MATERIAL', ROUND(COALESCE(c.output_materials, 0) * 1000000)::BIGINT,
    'COMPONENTS', ROUND(COALESCE(c.output_components, 0) * 1000000)::BIGINT,
    'COMPUTE', ROUND(COALESCE(c.output_compute, 0) * 1000000)::BIGINT
  ),
  jsonb_build_object(
    'ENERGY', ROUND(COALESCE(c.upkeep_energy, 0) * 1000000)::BIGINT,
    'FOOD', ROUND(COALESCE(c.upkeep_food, 0) * 1000000)::BIGINT,
    'MATERIAL', ROUND(COALESCE(c.upkeep_materials, 0) * 1000000)::BIGINT,
    'COMPONENTS', ROUND(COALESCE(c.upkeep_components, 0) * 1000000)::BIGINT,
    'COMPUTE', ROUND(COALESCE(c.upkeep_compute, 0) * 1000000)::BIGINT
  ),
  c.condition_curve_version,
  c.base_condition_decay_ppm,
  jsonb_build_object(
    'MATERIAL', c.repair_materials_per_point_ppm,
    'COMPONENTS', c.repair_components_per_point_ppm
  ),
  c.base_service_capacity_units,
  c.default_price_credit_units,
  c.operation_mode,
  earth_ratio_to_ppm(c.minimum_operating_ratio)
FROM building_catalog c
ON CONFLICT (catalog_id, rules_version) DO NOTHING;

CREATE OR REPLACE FUNCTION earth_building_rules_version(
  p_catalog_id TEXT, p_game_day BIGINT
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
  SELECT r.rules_version
  FROM building_economic_rule_versions r
  WHERE r.catalog_id = p_catalog_id
    AND r.effective_from_game_day <= p_game_day
    AND (r.effective_to_game_day IS NULL OR r.effective_to_game_day >= p_game_day)
  ORDER BY r.effective_from_game_day DESC, r.rules_version DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION earth_pin_building_rules_for_day(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building rule day or shard';
  END IF;

  UPDATE building_settlement_plans p
  SET rules_version = earth_building_rules_version(
    COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1)), p_game_day
  )
  FROM buildings b
  WHERE p.building_id = b.id
    AND p.game_day = p_game_day
    AND p.shard = p_shard
    AND earth_building_rules_version(
      COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1)), p_game_day
    ) IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_prepare_building_daily_settlement(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building daily settlement day or shard';
  END IF;

  PERFORM earth_pin_building_rules_for_day(p_game_day, p_shard);
  PERFORM earth_finalize_building_utilization(p_game_day, p_shard);
  PERFORM earth_apply_building_condition_efficiency(p_game_day, p_shard);
  PERFORM earth_finalize_building_condition(p_game_day, p_shard);
  PERFORM earth_apply_building_repair_policy(p_game_day, p_shard);

  SELECT COUNT(*) INTO v_count
  FROM building_settlement_plans
  WHERE game_day = p_game_day AND shard = p_shard;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE building_economic_rule_versions IS
  'Immutable building economics snapshots selected by effective game day for deterministic settlement and replay.';
