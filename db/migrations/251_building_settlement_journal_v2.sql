-- Building Economy V2 Plan 18: reproducible building settlement journal.

ALTER TABLE building_settlement_journals
  ADD COLUMN IF NOT EXISTS rules_version TEXT NOT NULL DEFAULT 'building-economy-v2';
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS condition_efficiency_ppm BIGINT NOT NULL DEFAULT 1000000;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS requested_inputs JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS allocated_inputs JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS shortages JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS utilization_ppm BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS base_output_units JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS actual_output_units JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS service_capacity_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS service_units_sold BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS gross_service_revenue_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS operating_expense_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS wear_points NUMERIC(20,8) NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS repair_requested_points NUMERIC(20,8) NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS repair_applied_points NUMERIC(20,8) NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS repair_resources JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS status_before TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS status_after TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS economic_batch_id BIGINT;
ALTER TABLE building_settlement_journals ADD COLUMN IF NOT EXISTS correlation_id TEXT;

CREATE OR REPLACE FUNCTION earth_write_building_settlement_journal(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building journal day or shard';
  END IF;

  WITH details AS (
    SELECT p.*, b.city_id, b.ownership_class, b.condition,
      c.output_energy, c.output_food, c.output_materials, c.output_components, c.output_compute,
      c.repair_materials_per_point, c.repair_components_per_point,
      COALESCE(a.service_units_sold, 0)::BIGINT AS sold,
      COALESCE(a.gross_revenue, 0)::BIGINT AS revenue,
      batch.id AS batch_id,
      format('building-settlement:%s:%s', p.game_day, p.shard) AS correlation
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    LEFT JOIN LATERAL (
      SELECT SUM(sa.delivered_units)::BIGINT AS service_units_sold,
        SUM(sa.delivered_units * sa.price_units)::BIGINT AS gross_revenue
      FROM service_allocations sa
      JOIN service_demand sd ON sd.id = sa.demand_id
      WHERE sa.game_day = p.game_day AND sa.building_id = p.building_id
        AND sa.status IN ('RESOLVED', 'POSTED')
    ) a ON TRUE
    LEFT JOIN building_economic_batches batch
      ON batch.game_day = p.game_day AND batch.shard = p.shard
    WHERE p.game_day = p_game_day AND p.shard = p_shard
  ), journal_data AS (
    SELECT d.*,
      COALESCE((SELECT jsonb_object_agg(req.k, to_jsonb(ROUND(COALESCE(req.v::NUMERIC, 0) * a.scale)::BIGINT))
        FROM jsonb_each_text(d.requirements) req(k, v)
        JOIN economic_assets a ON a.code = req.k), '{}'::JSONB) AS requested_values,
      COALESCE((SELECT jsonb_object_agg(req.k, to_jsonb(ROUND(COALESCE(req.v::NUMERIC, 0) * a.scale)::BIGINT))
        FROM jsonb_each_text(d.allocated_inputs) req(k, v)
        JOIN economic_assets a ON a.code = req.k), '{}'::JSONB) AS allocated_values,
      COALESCE((SELECT jsonb_object_agg(req.k, to_jsonb(ROUND(COALESCE(req.v::NUMERIC, 0) * a.scale)::BIGINT))
        FROM jsonb_each_text(d.consumption) req(k, v)
        JOIN economic_assets a ON a.code = req.k), '{}'::JSONB) AS consumed_values,
      COALESCE((SELECT jsonb_object_agg(req.k, to_jsonb(ROUND(GREATEST(0, COALESCE(req.v::NUMERIC, 0) - COALESCE((d.allocated_inputs ->> req.k)::NUMERIC, 0)) * a.scale)::BIGINT))
        FROM jsonb_each_text(d.requirements) req(k, v)
        JOIN economic_assets a ON a.code = req.k
        WHERE COALESCE(req.v, 0) > COALESCE((d.allocated_inputs ->> req.k)::NUMERIC, 0)), '{}'::JSONB) AS shortage_values,
      COALESCE((SELECT jsonb_object_agg(req.k, to_jsonb(ROUND(COALESCE(req.v::NUMERIC, 0) * a.scale)::BIGINT))
        FROM jsonb_each_text(d.production) req(k, v)
        JOIN economic_assets a ON a.code = req.k), '{}'::JSONB) AS actual_output,
      jsonb_build_object(
        'ENERGY', ROUND(COALESCE(d.output_energy, 0) * 1000000)::BIGINT,
        'FOOD', ROUND(COALESCE(d.output_food, 0) * 1000000)::BIGINT,
        'MATERIAL', ROUND(COALESCE(d.output_materials, 0) * 1000000)::BIGINT,
        'COMPONENTS', ROUND(COALESCE(d.output_components, 0) * 1000000)::BIGINT,
        'COMPUTE', ROUND(COALESCE(d.output_compute, 0) * 1000000)::BIGINT
      ) AS base_output,
      jsonb_build_object(
        CASE WHEN d.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END,
        ROUND(d.repair_points * CASE WHEN d.ownership_class = 'civic' THEN COALESCE(d.repair_materials_per_point, 1) ELSE COALESCE(d.repair_components_per_point, 1) END * 1000000)::BIGINT
      ) AS repair_resource_values
    FROM details d
  )
  INSERT INTO building_settlement_journals (
    id, building_id, city_id, day, ownership_class, rules_version,
    condition_start, condition_end, condition_efficiency_ppm,
    requested_inputs, allocated_inputs, consumed_units, shortages,
    utilization_ppm, base_output_units, actual_output_units,
    service_capacity_units, service_units_sold, gross_service_revenue_units,
    operating_expense_units, wear_points, repair_requested_points,
    repair_applied_points, repair_resources, status_before, status_after,
    economic_batch_id, correlation_id
  )
  SELECT gen_random_uuid(), building_id, city_id, game_day, ownership_class, rules_version,
    condition_before, condition_after, ROUND(condition_efficiency * 1000000)::BIGINT,
    requested_values, allocated_values, consumed_values, shortage_values,
    ROUND(utilization * 1000000)::BIGINT, base_output, actual_output,
    service_capacity, sold, revenue, operating_cost_units, wear,
    GREATEST(repair_target_condition - condition_before, 0), repair_points,
    repair_resource_values, operational_state_before, operational_state_after,
    batch_id, correlation
  FROM journal_data
  ON CONFLICT (building_id, day) DO UPDATE SET
    rules_version = EXCLUDED.rules_version,
    condition_start = EXCLUDED.condition_start,
    condition_end = EXCLUDED.condition_end,
    condition_efficiency_ppm = EXCLUDED.condition_efficiency_ppm,
    requested_inputs = EXCLUDED.requested_inputs,
    allocated_inputs = EXCLUDED.allocated_inputs,
    consumed_units = EXCLUDED.consumed_units,
    shortages = EXCLUDED.shortages,
    utilization_ppm = EXCLUDED.utilization_ppm,
    base_output_units = EXCLUDED.base_output_units,
    actual_output_units = EXCLUDED.actual_output_units,
    service_capacity_units = EXCLUDED.service_capacity_units,
    service_units_sold = EXCLUDED.service_units_sold,
    gross_service_revenue_units = EXCLUDED.gross_service_revenue_units,
    operating_expense_units = EXCLUDED.operating_expense_units,
    wear_points = EXCLUDED.wear_points,
    repair_requested_points = EXCLUDED.repair_requested_points,
    repair_applied_points = EXCLUDED.repair_applied_points,
    repair_resources = EXCLUDED.repair_resources,
    status_before = EXCLUDED.status_before,
    status_after = EXCLUDED.status_after,
    economic_batch_id = EXCLUDED.economic_batch_id,
    correlation_id = EXCLUDED.correlation_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE building_settlement_journals IS
  'Building Economy V2 audit/read model; reproducible from staged settlement plans and effects.';
