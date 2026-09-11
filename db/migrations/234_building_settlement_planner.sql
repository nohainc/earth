-- Building Economy V2 Plan 1: set-based, mutation-free settlement planning.
-- The plan is disposable working state. Economy V2 accounts and building state
-- are only changed by later resolution/posting phases.

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_plans (
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  owner_id TEXT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  city_id TEXT REFERENCES cities(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  requirements JSONB NOT NULL DEFAULT '{}'::JSONB,
  allocated_inputs JSONB NOT NULL DEFAULT '{}'::JSONB,
  utilization NUMERIC(12,6) NOT NULL DEFAULT 0 CHECK (utilization >= 0 AND utilization <= 1),
  condition_efficiency NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (condition_efficiency >= 0),
  consumption JSONB NOT NULL DEFAULT '{}'::JSONB,
  production JSONB NOT NULL DEFAULT '{}'::JSONB,
  service_capacity BIGINT NOT NULL DEFAULT 0,
  service_sales BIGINT NOT NULL DEFAULT 0,
  operating_expenses JSONB NOT NULL DEFAULT '{}'::JSONB,
  wear NUMERIC(12,6) NOT NULL DEFAULT 0,
  repair_points NUMERIC(12,6) NOT NULL DEFAULT 0,
  condition_before NUMERIC(10,4) NOT NULL,
  condition_after NUMERIC(10,4) NOT NULL,
  status_after TEXT NOT NULL,
  policy_code TEXT NOT NULL,
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (building_id, game_day)
);

CREATE INDEX IF NOT EXISTS building_settlement_plans_shard_idx
  ON building_settlement_plans (game_day, shard, building_id);
CREATE INDEX IF NOT EXISTS building_settlement_plans_owner_idx
  ON building_settlement_plans (game_day, owner_economic_id, building_id);

CREATE OR REPLACE FUNCTION earth_prepare_building_settlement(
  p_game_day BIGINT,
  p_shard SMALLINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Building settlement game day must be non-negative';
  END IF;
  IF p_shard IS NOT NULL AND (p_shard < 0 OR p_shard > 63) THEN
    RAISE EXCEPTION 'Building settlement shard must be between 0 and 63';
  END IF;

  INSERT INTO building_settlement_plans (
    building_id, owner_id, owner_economic_id, city_id, game_day, shard,
    requirements, allocated_inputs, utilization, condition_efficiency,
    consumption, production, service_capacity, service_sales,
    operating_expenses, wear, repair_points, condition_before, condition_after,
    status_after, policy_code, rules_version
  )
  SELECT b.id,
    CASE WHEN b.ownership_class = 'civic' THEN b.city_id ELSE b.owner_id END,
    owner.economic_id,
    b.city_id,
    p_game_day,
    earth_settlement_shard(owner.economic_id, 64),
    jsonb_build_object(
      'MATERIAL', COALESCE(bc.upkeep_materials, 0),
      'COMPONENTS', COALESCE(bc.upkeep_components, 0),
      'ENERGY', COALESCE(bc.upkeep_energy, 0),
      'COMPUTE', COALESCE(bc.upkeep_compute, 0),
      'FOOD', COALESCE(bc.upkeep_food, 0),
      'CREDIT', COALESCE(bc.operating_credits, 0)
    ),
    '{}'::JSONB,
    0,
    1,
    jsonb_build_object(
      'MATERIAL', COALESCE(bc.upkeep_materials, 0),
      'COMPONENTS', COALESCE(bc.upkeep_components, 0),
      'ENERGY', COALESCE(bc.upkeep_energy, 0),
      'COMPUTE', COALESCE(bc.upkeep_compute, 0),
      'FOOD', COALESCE(bc.upkeep_food, 0),
      'CREDIT', COALESCE(bc.operating_credits, 0)
    ),
    jsonb_build_object(
      'MATERIAL', COALESCE(bc.output_materials, 0),
      'COMPONENTS', COALESCE(bc.output_components, 0),
      'ENERGY', COALESCE(bc.output_energy, 0),
      'COMPUTE', COALESCE(bc.output_compute, 0),
      'FOOD', COALESCE(bc.output_food, 0)
    ),
    0,
    0,
    jsonb_build_object('CREDIT', COALESCE(bc.operating_credits, 0)),
    0,
    0,
    b.condition,
    b.condition,
    b.status,
    COALESCE(b.operating_policy, 'balanced'),
    'building-economy-v2-planner-1'
  FROM buildings b
  JOIN owner_registry owner
    ON owner.id = CASE WHEN b.ownership_class = 'civic' THEN b.city_id ELSE b.owner_id END
  LEFT JOIN building_catalog bc
    ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  WHERE b.status IN ('active', 'damaged')
    AND (p_shard IS NULL OR earth_settlement_shard(owner.economic_id, 64) = p_shard)
  ON CONFLICT (building_id, game_day) DO UPDATE SET
    owner_id = EXCLUDED.owner_id,
    owner_economic_id = EXCLUDED.owner_economic_id,
    city_id = EXCLUDED.city_id,
    shard = EXCLUDED.shard,
    requirements = EXCLUDED.requirements,
    consumption = EXCLUDED.consumption,
    production = EXCLUDED.production,
    operating_expenses = EXCLUDED.operating_expenses,
    condition_before = EXCLUDED.condition_before,
    condition_after = EXCLUDED.condition_after,
    status_after = EXCLUDED.status_after,
    policy_code = EXCLUDED.policy_code,
    rules_version = EXCLUDED.rules_version,
    created_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE building_settlement_plans IS
  'Disposable set-based building settlement plan; planning never mutates balances or building state.';
