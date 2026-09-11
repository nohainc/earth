-- Building Economy V2 Plan 7: separate wear, routine maintenance and repair.

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS base_condition_decay NUMERIC(12,6) NOT NULL DEFAULT 1;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS maintenance_wear_multiplier NUMERIC(12,6) NOT NULL DEFAULT 2;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS repair_target_condition NUMERIC(10,4) NOT NULL DEFAULT 100;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS repair_materials_per_point NUMERIC(20,8) NOT NULL DEFAULT 1;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS repair_components_per_point NUMERIC(20,8) NOT NULL DEFAULT 1;

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS maintenance_fulfillment NUMERIC(12,6) NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION earth_finalize_building_condition(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building condition day or shard';
  END IF;

  WITH inputs AS (
    SELECT p.building_id, p.game_day, p.owner_economic_id, p.condition_before,
      p.utilization, p.operation_mode, p.minimum_operating_ratio,
      COALESCE(c.base_condition_decay, 1) AS base_decay,
      COALESCE(c.maintenance_wear_multiplier, 2) AS maintenance_multiplier,
      COALESCE(c.repair_target_condition, 100) AS repair_target,
      CASE WHEN b.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END AS repair_code,
      CASE WHEN b.ownership_class = 'civic' THEN COALESCE(c.repair_materials_per_point, 1)
           ELSE COALESCE(c.repair_components_per_point, 1) END AS repair_cost_per_point,
      COALESCE((p.requirements ->> 'MATERIAL')::NUMERIC, 0) AS material_required,
      COALESCE((p.requirements ->> 'COMPONENTS')::NUMERIC, 0) AS components_required,
      COALESCE((p.requirements ->> 'ENERGY')::NUMERIC, 0) AS energy_required,
      COALESCE((p.requirements ->> 'COMPUTE')::NUMERIC, 0) AS compute_required,
      COALESCE((p.requirements ->> 'FOOD')::NUMERIC, 0) AS food_required,
      COALESCE((p.allocated_inputs ->> 'MATERIAL')::NUMERIC, 0) AS material_allocated,
      COALESCE((p.allocated_inputs ->> 'COMPONENTS')::NUMERIC, 0) AS components_allocated,
      COALESCE((p.allocated_inputs ->> 'ENERGY')::NUMERIC, 0) AS energy_allocated,
      COALESCE((p.allocated_inputs ->> 'COMPUTE')::NUMERIC, 0) AS compute_allocated,
      COALESCE((p.allocated_inputs ->> 'FOOD')::NUMERIC, 0) AS food_allocated
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE p.game_day = p_game_day AND p.shard = p_shard
  ), ratios AS (
    SELECT i.*,
      LEAST(
        CASE WHEN material_required = 0 THEN 1 ELSE material_allocated / material_required END,
        CASE WHEN components_required = 0 THEN 1 ELSE components_allocated / components_required END,
        CASE WHEN energy_required = 0 THEN 1 ELSE energy_allocated / energy_required END,
        CASE WHEN compute_required = 0 THEN 1 ELSE compute_allocated / compute_required END,
        CASE WHEN food_required = 0 THEN 1 ELSE food_allocated / food_required END
      ) AS maintenance_ratio
    FROM inputs i
  ), remaining AS (
    SELECT r.*,
      GREATEST(0, COALESCE((o.available_units ->> r.repair_code)::NUMERIC, 0)
        - COALESCE((SELECT SUM(a.allocated_units)::NUMERIC / asset.scale
          FROM building_settlement_allocations a
          JOIN economic_assets asset ON asset.id = a.asset_id AND asset.code = r.repair_code
          WHERE a.owner_economic_id = r.owner_economic_id AND a.game_day = r.game_day), 0)) AS repair_available
    FROM ratios r
    LEFT JOIN building_settlement_owner_inputs o
      ON o.owner_economic_id = r.owner_economic_id AND o.game_day = r.game_day
  ), calculated AS (
    SELECT r.*,
      LEAST(1, GREATEST(0, r.maintenance_ratio)) AS final_maintenance,
      r.base_decay * CASE WHEN r.utilization > 0 THEN r.utilization ELSE 0.1 END
        * (1 + r.maintenance_multiplier * (1 - LEAST(1, GREATEST(0, r.maintenance_ratio)))) AS calculated_wear,
      LEAST(GREATEST(r.repair_target - r.condition_before, 0),
        CASE WHEN r.repair_cost_per_point > 0 THEN r.repair_available / r.repair_cost_per_point ELSE 0 END) AS calculated_repair
    FROM remaining r
  )
  UPDATE building_settlement_plans p
  SET maintenance_fulfillment = c.final_maintenance,
      wear = c.calculated_wear,
      repair_points = c.calculated_repair,
      condition_after = GREATEST(0, LEAST(100, c.condition_before - c.calculated_wear + c.calculated_repair))
  FROM calculated c
  WHERE p.building_id = c.building_id AND p.game_day = c.game_day;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN building_catalog.maintenance_wear_multiplier IS
  'Additional wear multiplier when routine maintenance is unfulfilled.';
