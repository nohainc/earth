-- Building Economy V2 Plan 10: explicit recoverable operational states.

ALTER TABLE buildings ADD COLUMN IF NOT EXISTS operational_state TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_operational_state_ck;
ALTER TABLE buildings ADD CONSTRAINT buildings_operational_state_ck
  CHECK (operational_state IN ('ACTIVE', 'DEGRADED', 'OFFLINE', 'DESTROYED'));

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS operational_state_before TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS operational_state_after TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE building_settlement_plans DROP CONSTRAINT IF EXISTS building_settlement_plans_operational_state_ck;
ALTER TABLE building_settlement_plans ADD CONSTRAINT building_settlement_plans_operational_state_ck
  CHECK (operational_state_after IN ('ACTIVE', 'DEGRADED', 'OFFLINE', 'DESTROYED'));

CREATE OR REPLACE FUNCTION earth_finalize_building_operational_state(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building operational state day or shard';
  END IF;

  UPDATE building_settlement_plans p
  SET operational_state_before = COALESCE(b.operational_state, 'ACTIVE'),
      operational_state_after = CASE
        WHEN COALESCE(b.operational_state, 'ACTIVE') = 'DESTROYED'
          OR b.status IN ('derelict', 'decommissioned') THEN 'DESTROYED'
        WHEN p.condition_after <= 0 THEN 'OFFLINE'
        WHEN p.condition_after < 40 THEN 'DEGRADED'
        ELSE 'ACTIVE'
      END,
      status_after = CASE
        WHEN COALESCE(b.operational_state, 'ACTIVE') = 'DESTROYED'
          OR b.status IN ('derelict', 'decommissioned') THEN 'decommissioned'
        ELSE b.status
      END
  FROM buildings b
  WHERE p.building_id = b.id AND p.game_day = p_game_day AND p.shard = p_shard;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN buildings.operational_state IS
  'Recoverable operating state; OFFLINE buildings remain eligible for repair.';
