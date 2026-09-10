-- Canonical implementation for the current daily_settlement_profile_runs
-- contract. This replaces an obsolete function body that targeted a retired
-- audit-table schema and prevented all daily settlement from committing.
CREATE OR REPLACE FUNCTION earth_catchup_owner_settlement(
  p_owner_id TEXT,
  p_target_day BIGINT DEFAULT NULL
)
RETURNS TABLE(owner_id TEXT, elapsed_days INTEGER, last_settled_day BIGINT, settled BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  v_target_day BIGINT;
  v_profile daily_settlement_profiles%ROWTYPE;
  v_elapsed INTEGER;
  v_delta JSONB;
BEGIN
  IF p_target_day IS NULL THEN
    SELECT earth_game_day_from_total_minutes(total_game_minutes)
      INTO v_target_day FROM earth_get_current_game_time();
  ELSE
    v_target_day := p_target_day;
  END IF;

  SELECT * INTO v_profile
  FROM daily_settlement_profiles p
  WHERE p.owner_id = p_owner_id
  FOR UPDATE;
  IF NOT FOUND OR v_profile.status <> 'clean' THEN
    RETURN QUERY SELECT p_owner_id, 0, COALESCE(v_profile.last_settled_game_day, v_target_day), FALSE;
    RETURN;
  END IF;

  v_elapsed := GREATEST(0, v_target_day - v_profile.last_settled_game_day)::INTEGER;
  IF v_elapsed = 0 THEN
    RETURN QUERY SELECT p_owner_id, 0, v_profile.last_settled_game_day, FALSE;
    RETURN;
  END IF;

  v_delta := jsonb_build_object(
    'energy', v_profile.energy_delta * v_elapsed,
    'food', v_profile.food_delta * v_elapsed,
    'material', v_profile.materials_delta * v_elapsed,
    'components', v_profile.components_delta * v_elapsed,
    'compute', v_profile.compute_delta * v_elapsed
  );

  INSERT INTO resource_balances (owner_id, resource, amount)
  SELECT p_owner_id, entry.key,
         GREATEST(0, (entry.value::TEXT)::NUMERIC)
  FROM jsonb_each(v_delta) entry
  WHERE (entry.value::TEXT)::NUMERIC <> 0
  ON CONFLICT (owner_id, resource) DO UPDATE
    SET amount = GREATEST(0, resource_balances.amount + EXCLUDED.amount);

  INSERT INTO daily_settlement_profile_runs (
    owner_id, game_day, profile_version, last_settled_game_day,
    elapsed_days, mode, expected_delta
  ) VALUES (
    p_owner_id, v_target_day, v_profile.profile_version,
    v_profile.last_settled_game_day, v_elapsed, 'applied', v_delta
  ) ON CONFLICT (owner_id, game_day) DO NOTHING;

  UPDATE daily_settlement_profiles
  SET last_settled_game_day = v_target_day, updated_at = CURRENT_TIMESTAMP
  WHERE owner_id = p_owner_id;

  RETURN QUERY SELECT p_owner_id, v_elapsed, v_target_day, TRUE;
END;
$$;
