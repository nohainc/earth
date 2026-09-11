-- Building Economy V2 Plan 9: repair is applied after today's operation.

CREATE OR REPLACE FUNCTION earth_prepare_building_daily_settlement(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building daily settlement day or shard';
  END IF;

  -- Fixed order: utilization -> start-of-day condition efficiency -> wear ->
  -- repair. The repair result is stored only in condition_after and cannot
  -- influence today's already-calculated production or service capacity.
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

COMMENT ON FUNCTION earth_prepare_building_daily_settlement(BIGINT, SMALLINT) IS
  'Prepares one shard in deterministic order; repairs affect the next day, not today output.';
