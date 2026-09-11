-- Building Economy V2 Plan 3: deterministic owner-level input allocation.

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS settlement_priority INTEGER NOT NULL DEFAULT 100;
ALTER TABLE buildings
  DROP CONSTRAINT IF EXISTS buildings_settlement_priority_ck;
ALTER TABLE buildings
  ADD CONSTRAINT buildings_settlement_priority_ck CHECK (settlement_priority BETWEEN 0 AND 1000);

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS settlement_priority INTEGER NOT NULL DEFAULT 100;

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_allocations (
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  requested_units BIGINT NOT NULL CHECK (requested_units >= 0),
  allocated_units BIGINT NOT NULL CHECK (allocated_units >= 0),
  allocation_remainder NUMERIC(30,12) NOT NULL DEFAULT 0,
  PRIMARY KEY (building_id, game_day, asset_id)
);
CREATE INDEX IF NOT EXISTS building_settlement_allocations_owner_idx
  ON building_settlement_allocations (game_day, owner_economic_id, asset_id, building_id);

CREATE OR REPLACE FUNCTION earth_allocate_building_inputs(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_owner RECORD;
  v_asset RECORD;
  v_priority RECORD;
  v_available BIGINT;
  v_used BIGINT;
  v_class_requested BIGINT;
  v_class_allocated BIGINT;
  v_count BIGINT := 0;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building allocation day or shard';
  END IF;

  -- The planner remains usable on its own; copy the current building policy
  -- into the staged rows before allocation begins.
  UPDATE building_settlement_plans p
  SET settlement_priority = b.settlement_priority
  FROM buildings b
  WHERE p.building_id = b.id AND p.game_day = p_game_day AND p.shard = p_shard;

  DELETE FROM building_settlement_allocations
  WHERE game_day = p_game_day AND owner_economic_id IN (
    SELECT owner_economic_id FROM building_settlement_plans
    WHERE game_day = p_game_day AND shard = p_shard
  );

  FOR v_owner IN
    SELECT DISTINCT owner_economic_id
    FROM building_settlement_plans
    WHERE game_day = p_game_day AND shard = p_shard
  LOOP
    FOR v_asset IN
      SELECT id, code, scale FROM economic_assets ORDER BY id
    LOOP
      v_available := COALESCE((
        SELECT (available_units ->> v_asset.code)::BIGINT
        FROM building_settlement_owner_inputs
        WHERE owner_economic_id = v_owner.owner_economic_id AND game_day = p_game_day
      ), 0);
      v_used := 0;

      FOR v_priority IN
        SELECT DISTINCT p.settlement_priority
        FROM building_settlement_plans p
        WHERE p.game_day = p_game_day AND p.shard = p_shard
          AND p.owner_economic_id = v_owner.owner_economic_id
          AND COALESCE((p.requirements ->> v_asset.code)::NUMERIC, 0) > 0
        ORDER BY p.settlement_priority DESC
      LOOP
        SELECT COALESCE(SUM(ROUND((p.requirements ->> v_asset.code)::NUMERIC * v_asset.scale)), 0)::BIGINT
        INTO v_class_requested
        FROM building_settlement_plans p
        WHERE p.game_day = p_game_day AND p.shard = p_shard
          AND p.owner_economic_id = v_owner.owner_economic_id
          AND p.settlement_priority = v_priority.settlement_priority
          AND COALESCE((p.requirements ->> v_asset.code)::NUMERIC, 0) > 0;

        v_class_allocated := LEAST(v_class_requested, GREATEST(v_available - v_used, 0));

        WITH requested AS (
          SELECT p.building_id,
            ROUND((p.requirements ->> v_asset.code)::NUMERIC * v_asset.scale)::BIGINT AS requested_units
          FROM building_settlement_plans p
          WHERE p.game_day = p_game_day AND p.shard = p_shard
            AND p.owner_economic_id = v_owner.owner_economic_id
            AND p.settlement_priority = v_priority.settlement_priority
            AND COALESCE((p.requirements ->> v_asset.code)::NUMERIC, 0) > 0
        ), fractions AS (
          SELECT r.*, (r.requested_units::NUMERIC * v_class_allocated / NULLIF(v_class_requested, 0)) AS exact_units
          FROM requested r
        ), bases AS (
          SELECT f.*, FLOOR(f.exact_units)::BIGINT AS base_units,
            f.exact_units - FLOOR(f.exact_units) AS remainder
          FROM fractions f
        ), ranked AS (
          SELECT b.*, ROW_NUMBER() OVER (ORDER BY b.remainder DESC, b.building_id) AS remainder_rank,
            (v_class_allocated - SUM(b.base_units) OVER ()) AS remainder_units
          FROM bases b
        )
        INSERT INTO building_settlement_allocations (
          building_id, game_day, owner_economic_id, asset_id,
          requested_units, allocated_units, allocation_remainder
        )
        SELECT building_id, p_game_day, v_owner.owner_economic_id, v_asset.id,
          requested_units,
          base_units + CASE WHEN remainder_rank <= remainder_units THEN 1 ELSE 0 END,
          remainder
        FROM ranked
        ON CONFLICT (building_id, game_day, asset_id) DO UPDATE SET
          requested_units = EXCLUDED.requested_units,
          allocated_units = EXCLUDED.allocated_units,
          allocation_remainder = EXCLUDED.allocation_remainder;

        v_used := v_used + v_class_allocated;
      END LOOP;
    END LOOP;
  END LOOP;

  WITH values_by_building AS (
    SELECT p.building_id, p.game_day,
      jsonb_object_agg(a.code, to_jsonb(x.allocated_units::NUMERIC / a.scale)) AS allocated_inputs,
      MIN(CASE WHEN x.requested_units = 0 THEN 1::NUMERIC ELSE x.allocated_units::NUMERIC / x.requested_units END) AS utilization
    FROM building_settlement_plans p
    JOIN building_settlement_allocations x ON x.building_id = p.building_id AND x.game_day = p.game_day
    JOIN economic_assets a ON a.id = x.asset_id
    WHERE p.game_day = p_game_day AND p.shard = p_shard
    GROUP BY p.building_id, p.game_day
  )
  UPDATE building_settlement_plans p
  SET allocated_inputs = v.allocated_inputs,
      consumption = v.allocated_inputs,
      utilization = LEAST(1, GREATEST(0, COALESCE(v.utilization, 0)))
  FROM values_by_building v
  WHERE p.building_id = v.building_id AND p.game_day = v.game_day;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN buildings.settlement_priority IS
  'Deterministic resource-allocation priority; higher values are allocated first.';
