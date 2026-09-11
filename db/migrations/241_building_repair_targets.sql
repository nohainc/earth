-- Building Economy V2 Plan 8: explicit repair targets and priorities.

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS auto_repair_target_condition NUMERIC(10,4) NOT NULL DEFAULT 90;
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS repair_priority INTEGER NOT NULL DEFAULT 100;
ALTER TABLE buildings
  DROP CONSTRAINT IF EXISTS buildings_auto_repair_target_condition_ck;
ALTER TABLE buildings
  ADD CONSTRAINT buildings_auto_repair_target_condition_ck
  CHECK (auto_repair_target_condition BETWEEN 0 AND 100);
ALTER TABLE buildings
  DROP CONSTRAINT IF EXISTS buildings_repair_priority_ck;
ALTER TABLE buildings
  ADD CONSTRAINT buildings_repair_priority_ck CHECK (repair_priority BETWEEN 0 AND 1000);

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS auto_repair_enabled BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS repair_target_condition NUMERIC(10,4) NOT NULL DEFAULT 90;
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS repair_priority INTEGER NOT NULL DEFAULT 100;

CREATE OR REPLACE FUNCTION earth_apply_building_repair_policy(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building repair policy day or shard';
  END IF;

  WITH source_data AS (
    SELECT p.building_id, p.game_day, p.condition_before, p.wear,
      b.auto_repair_enabled,
      COALESCE(b.auto_repair_target_condition, 90) AS target_condition,
      b.repair_priority,
      CASE WHEN b.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END AS repair_code,
      CASE WHEN b.ownership_class = 'civic' THEN COALESCE(c.repair_materials_per_point, 1)
           ELSE COALESCE(c.repair_components_per_point, 1) END AS cost_per_point,
      GREATEST(0, COALESCE((o.available_units ->> CASE WHEN b.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END)::NUMERIC, 0)
        - COALESCE((SELECT SUM(a.allocated_units)::NUMERIC / asset.scale
          FROM building_settlement_allocations a
          JOIN economic_assets asset ON asset.id = a.asset_id
           AND asset.code = CASE WHEN b.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END
          WHERE a.owner_economic_id = p.owner_economic_id AND a.game_day = p.game_day), 0)) AS remaining_repair_resource
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    LEFT JOIN building_settlement_owner_inputs o
      ON o.owner_economic_id = p.owner_economic_id AND o.game_day = p.game_day
    WHERE p.game_day = p_game_day AND p.shard = p_shard
  ), calculated AS (
    SELECT s.*,
      CASE WHEN s.auto_repair_enabled AND s.cost_per_point > 0
        THEN LEAST(GREATEST(s.target_condition - s.condition_before, 0), s.remaining_repair_resource / s.cost_per_point)
        ELSE 0 END AS repair_points
    FROM source_data s
  )
  UPDATE building_settlement_plans p
  SET auto_repair_enabled = c.auto_repair_enabled,
      repair_target_condition = c.target_condition,
      repair_priority = c.repair_priority,
      repair_points = c.repair_points,
      condition_after = GREATEST(0, LEAST(100, c.condition_before - c.wear + c.repair_points))
  FROM calculated c
  WHERE p.building_id = c.building_id AND p.game_day = c.game_day;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN buildings.auto_repair_target_condition IS
  'Target condition for automatic repair; resources may produce only partial recovery.';
