-- Building Economy V2 Plan 4: continuous utilization with explicit operating modes.

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS operation_mode TEXT NOT NULL DEFAULT 'SCALABLE';
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS minimum_operating_ratio NUMERIC(12,6) NOT NULL DEFAULT 0;
ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_operation_mode_ck;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_operation_mode_ck CHECK (operation_mode IN ('SCALABLE', 'BINARY', 'THRESHOLD'));
ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_minimum_operating_ratio_ck;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_minimum_operating_ratio_ck CHECK (minimum_operating_ratio BETWEEN 0 AND 1);

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS operation_mode TEXT NOT NULL DEFAULT 'SCALABLE';
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS minimum_operating_ratio NUMERIC(12,6) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION earth_finalize_building_utilization(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building utilization day or shard';
  END IF;

  UPDATE building_settlement_plans p
  SET operation_mode = COALESCE(c.operation_mode, 'SCALABLE'),
      minimum_operating_ratio = COALESCE(c.minimum_operating_ratio, 0)
  FROM buildings b
  LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  WHERE p.building_id = b.id AND p.game_day = p_game_day AND p.shard = p_shard;

  WITH base AS (
    SELECT p.*,
      CASE WHEN NOT EXISTS (
        SELECT 1 FROM building_settlement_allocations a
        WHERE a.building_id = p.building_id AND a.game_day = p.game_day
      ) THEN 1::NUMERIC ELSE LEAST(1, GREATEST(0, p.utilization)) END AS fulfillment
    FROM building_settlement_plans p
    WHERE p.game_day = p_game_day AND p.shard = p_shard
  ), normalized AS (
    SELECT b.*,
      CASE b.operation_mode
        WHEN 'BINARY' THEN CASE WHEN b.fulfillment >= 1 THEN 1::NUMERIC ELSE 0::NUMERIC END
        WHEN 'THRESHOLD' THEN CASE WHEN b.fulfillment >= b.minimum_operating_ratio THEN b.fulfillment ELSE 0::NUMERIC END
        ELSE b.fulfillment
      END AS effective_utilization
    FROM base b
  ), updated AS (
    UPDATE building_settlement_plans p
    SET utilization = n.effective_utilization,
        consumption = COALESCE(consumption_values.values, '{}'::JSONB),
        production = COALESCE(production_values.values, '{}'::JSONB),
        operating_expenses = jsonb_build_object(
          'CREDIT', ROUND(COALESCE((p.requirements ->> 'CREDIT')::NUMERIC, 0) * n.effective_utilization, 6)
        ),
        service_capacity = COALESCE(ROUND(c.output_credits * 100 * n.effective_utilization), 0)::BIGINT
    FROM normalized n
    LEFT JOIN LATERAL (
      SELECT jsonb_object_agg(k, to_jsonb(ROUND((v::NUMERIC) * n.effective_utilization, 6))) AS values
      FROM jsonb_each_text(p.requirements) inputs(k, v)
      WHERE k <> 'CREDIT' AND (v::NUMERIC) > 0
    ) consumption_values ON TRUE
    LEFT JOIN LATERAL (
      SELECT jsonb_object_agg(k, to_jsonb(ROUND((v::NUMERIC) * n.effective_utilization, 6))) AS values
      FROM jsonb_each_text(p.production) outputs(k, v)
      WHERE (v::NUMERIC) > 0
    ) production_values ON TRUE
    LEFT JOIN buildings b ON b.id = p.building_id
    LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE p.building_id = n.building_id AND p.game_day = n.game_day
    RETURNING p.building_id
  )
  SELECT COUNT(*) INTO v_count FROM updated;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN building_catalog.operation_mode IS
  'Shortage behavior: SCALABLE, BINARY, or THRESHOLD.';
