-- Stored Function: earth_rebuild_settlement_profile
--
-- Authoritative server-side profile builder: aggregates active building outputs
-- and upkeeps into clean daily deltas in daily_settlement_profiles.
CREATE OR REPLACE FUNCTION earth_rebuild_settlement_profile(
  p_owner_id TEXT,
  p_game_day BIGINT DEFAULT NULL
)
RETURNS TABLE (
  owner_id TEXT,
  profile_version INTEGER,
  status TEXT,
  energy_delta NUMERIC(20,6),
  food_delta NUMERIC(20,6),
  materials_delta NUMERIC(20,6),
  components_delta NUMERIC(20,6),
  compute_delta NUMERIC(20,6)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_owner_kind TEXT;
  v_game_day BIGINT;
  v_energy_delta NUMERIC(20,6) := 0;
  v_food_delta NUMERIC(20,6) := 0;
  v_materials_delta NUMERIC(20,6) := 0;
  v_components_delta NUMERIC(20,6) := 0;
  v_compute_delta NUMERIC(20,6) := 0;
  v_b RECORD;
  v_eff NUMERIC;
  v_cond_cost NUMERIC;
  v_out_mult NUMERIC;
  v_cost_mult NUMERIC;
  v_out_amount NUMERIC(20,6);
BEGIN
  -- Determine current game day if omitted based on genesis_at epoch
  IF p_game_day IS NULL THEN
    SELECT t.game_day INTO v_game_day FROM earth_get_current_game_time() t;
    v_game_day := COALESCE(v_game_day, 1);
  ELSE
    v_game_day := p_game_day;
  END IF;

  -- Lock profile
  SELECT p.owner_kind INTO v_owner_kind
  FROM daily_settlement_profiles p
  WHERE p.owner_id = p_owner_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- If no profile exists, initialize a default clean profile for this owner
    INSERT INTO daily_settlement_profiles (
      id, owner_id, owner_kind, status, profile_version,
      effective_game_day, last_settled_game_day,
      energy_delta, food_delta, materials_delta, components_delta, compute_delta,
      created_at, updated_at
    ) VALUES (
      gen_random_uuid(), p_owner_id, 'human', 'clean', 1,
      v_game_day, v_game_day,
      0, 0, 0, 0, 0,
      NOW(), NOW()
    )
    ON CONFLICT (owner_id) DO NOTHING;

    v_owner_kind := 'human';
  END IF;

  -- Iterate through active buildings owned by this entity
  FOR v_b IN
    SELECT
      b.resource_output_type,
      b.resource_output_amount,
      b.operating_policy,
      b.condition
    FROM buildings b
    WHERE (
      (v_owner_kind = 'city' AND b.city_id = p_owner_id AND b.ownership_class = 'civic')
      OR (v_owner_kind <> 'city' AND b.owner_id = p_owner_id AND b.ownership_class = 'private')
    )
    AND b.status = 'active'
  LOOP
    -- Policy multipliers
    IF v_b.operating_policy = 'high_output' THEN
      v_out_mult := 1.3;
      v_cost_mult := 1.4;
    ELSIF v_b.operating_policy IN ('frugal', 'eco_reserve') THEN
      v_out_mult := 0.75;
      v_cost_mult := 0.7;
    ELSIF v_b.operating_policy = 'halted' THEN
      v_out_mult := 0.0;
      v_cost_mult := 0.2;
    ELSE
      v_out_mult := 1.0;
      v_cost_mult := 1.0;
    END IF;

    -- Condition efficiency & degradation cost
    IF v_b.condition >= 80.0 THEN
      v_eff := 1.0;
      v_cond_cost := 1.0;
    ELSIF v_b.condition >= 50.0 THEN
      v_eff := 0.75;
      v_cond_cost := 1.15;
    ELSIF v_b.condition >= 20.0 THEN
      v_eff := 0.4;
      v_cond_cost := 1.4;
    ELSE
      v_eff := 0.1;
      v_cond_cost := 2.0;
    END IF;

    -- Output addition
    v_out_amount := COALESCE(v_b.resource_output_amount, 0) * v_out_mult * v_eff;
    IF v_b.resource_output_type = 'energy' THEN
      v_energy_delta := v_energy_delta + v_out_amount;
    ELSIF v_b.resource_output_type = 'food' THEN
      v_food_delta := v_food_delta + v_out_amount;
    ELSIF v_b.resource_output_type = 'material' THEN
      v_materials_delta := v_materials_delta + v_out_amount;
    ELSIF v_b.resource_output_type = 'components' THEN
      v_components_delta := v_components_delta + v_out_amount;
    ELSIF v_b.resource_output_type = 'compute' THEN
      v_compute_delta := v_compute_delta + v_out_amount;
    END IF;
  END LOOP;

  -- Update daily_settlement_profiles
  UPDATE daily_settlement_profiles
  SET
    status = 'clean',
    profile_version = profile_version + 1,
    effective_game_day = v_game_day,
    energy_delta = v_energy_delta,
    food_delta = v_food_delta,
    materials_delta = v_materials_delta,
    components_delta = v_components_delta,
    compute_delta = v_compute_delta,
    updated_at = NOW()
  WHERE daily_settlement_profiles.owner_id = p_owner_id;

  RETURN QUERY
  SELECT
    p.owner_id,
    p.profile_version,
    p.status,
    p.energy_delta,
    p.food_delta,
    p.materials_delta,
    p.components_delta,
    p.compute_delta
  FROM daily_settlement_profiles p
  WHERE p.owner_id = p_owner_id;
END;
$$;
