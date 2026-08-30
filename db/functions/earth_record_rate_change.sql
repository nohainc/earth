-- Stored Function: earth_record_rate_change
--
-- Authoritative server-side procedure to compute and record timestamped
-- rate change snapshots for all 6 resources whenever an owner's building
-- portfolio, policy, or active state changes.
CREATE OR REPLACE FUNCTION earth_record_rate_change(
  p_owner_id TEXT,
  p_trigger_event TEXT,
  p_trigger_entity_id TEXT DEFAULT NULL,
  p_game_day BIGINT DEFAULT NULL,
  p_game_minute INTEGER DEFAULT NULL
)
RETURNS TABLE (
  owner_id TEXT,
  game_day BIGINT,
  game_minute INTEGER,
  created_at TIMESTAMPTZ,
  trigger_event TEXT,
  trigger_entity_id TEXT,
  resource TEXT,
  gross_inflow NUMERIC(20,6),
  gross_outflow NUMERIC(20,6),
  net_daily_rate NUMERIC(20,6)
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  v_game_day BIGINT;
  v_game_minute INTEGER;
  v_now TIMESTAMPTZ := NOW();
  v_owner_kind TEXT;

  -- Inflows
  v_in_credits NUMERIC(20,6) := 0;
  v_in_energy NUMERIC(20,6) := 0;
  v_in_food NUMERIC(20,6) := 0;
  v_in_material NUMERIC(20,6) := 0;
  v_in_components NUMERIC(20,6) := 0;
  v_in_compute NUMERIC(20,6) := 0;

  -- Outflows
  v_out_credits NUMERIC(20,6) := 0;
  v_out_energy NUMERIC(20,6) := 0;
  v_out_food NUMERIC(20,6) := 0;
  v_out_material NUMERIC(20,6) := 0;
  v_out_components NUMERIC(20,6) := 0;
  v_out_compute NUMERIC(20,6) := 0;

  v_b RECORD;
  v_eff NUMERIC;
  v_cond_cost NUMERIC;
  v_out_mult NUMERIC;
  v_cost_mult NUMERIC;
  v_out_amount NUMERIC(20,6);
BEGIN
  IF p_owner_id IS NULL OR LENGTH(TRIM(p_owner_id)) = 0 THEN
    RAISE EXCEPTION 'earth_record_rate_change requires a valid owner_id';
  END IF;

  IF p_game_day IS NULL THEN
    SELECT t.game_day, t.game_minute INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;
    v_game_day := COALESCE(v_game_day, 1);
    v_game_minute := COALESCE(v_game_minute, 0);
  ELSE
    v_game_day := p_game_day;
    v_game_minute := COALESCE(p_game_minute, 0);
  END IF;

  SELECT p.owner_kind INTO v_owner_kind
  FROM daily_settlement_profiles p
  WHERE p.owner_id = p_owner_id;

  v_owner_kind := COALESCE(v_owner_kind, 'human');

  -- Aggregate active buildings
  FOR v_b IN
    SELECT
      b.resource_output_type,
      b.resource_output_amount,
      b.upkeep_energy,
      b.upkeep_food,
      b.upkeep_materials,
      b.upkeep_components,
      b.upkeep_compute,
      b.daily_operating_credits,
      b.operating_policy,
      b.condition
    FROM buildings b
    WHERE (
      (v_owner_kind = 'city' AND b.city_id = p_owner_id AND b.ownership_class = 'civic')
      OR (v_owner_kind <> 'city' AND b.owner_id = p_owner_id AND b.ownership_class = 'private')
    )
    AND b.status = 'active'
  LOOP
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

    v_eff := GREATEST(0.1, LEAST(1.0, (v_b.condition / 100.0))) * v_out_mult;
    v_cond_cost := (1.0 + (GREATEST(0, 100.0 - v_b.condition) / 200.0)) * v_cost_mult;

    -- Inflow
    v_out_amount := ROUND(v_b.resource_output_amount * v_eff, 6);
    IF v_b.resource_output_type = 'credits' THEN
      v_in_credits := v_in_credits + v_out_amount;
    ELSIF v_b.resource_output_type = 'energy' THEN
      v_in_energy := v_in_energy + v_out_amount;
    ELSIF v_b.resource_output_type = 'food' THEN
      v_in_food := v_in_food + v_out_amount;
    ELSIF v_b.resource_output_type = 'material' THEN
      v_in_material := v_in_material + v_out_amount;
    ELSIF v_b.resource_output_type = 'components' THEN
      v_in_components := v_in_components + v_out_amount;
    ELSIF v_b.resource_output_type = 'compute' THEN
      v_in_compute := v_in_compute + v_out_amount;
    END IF;

    -- Outflow
    v_out_credits := v_out_credits + ROUND(COALESCE(v_b.daily_operating_credits, 0) * v_cond_cost, 6);
    v_out_energy := v_out_energy + ROUND(v_b.upkeep_energy * v_cond_cost, 6);
    v_out_food := v_out_food + ROUND(v_b.upkeep_food * v_cond_cost, 6);
    v_out_material := v_out_material + ROUND(v_b.upkeep_materials * v_cond_cost, 6);
    v_out_components := v_out_components + ROUND(v_b.upkeep_components * v_cond_cost, 6);
    v_out_compute := v_out_compute + ROUND(v_b.upkeep_compute * v_cond_cost, 6);
  END LOOP;

  -- Insert snapshot rows for all 6 resources
  INSERT INTO resource_rate_history (
    id, owner_id, game_day, game_minute, created_at,
    trigger_event, trigger_entity_id, resource,
    gross_inflow, gross_outflow, net_daily_rate
  ) VALUES
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'credits', v_in_credits, v_out_credits, (v_in_credits - v_out_credits)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'energy', v_in_energy, v_out_energy, (v_in_energy - v_out_energy)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'food', v_in_food, v_out_food, (v_in_food - v_out_food)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'material', v_in_material, v_out_material, (v_in_material - v_out_material)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'components', v_in_components, v_out_components, (v_in_components - v_out_components)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'compute', v_in_compute, v_out_compute, (v_in_compute - v_out_compute));

  -- Also update daily_settlement_profiles with the new clean rates
  INSERT INTO daily_settlement_profiles (
    owner_id, owner_kind, status, profile_version,
    effective_game_day, last_settled_game_day,
    credits_delta, energy_delta, food_delta, materials_delta, components_delta, compute_delta,
    updated_at
  ) VALUES (
    p_owner_id, v_owner_kind, 'clean', 1,
    v_game_day, v_game_day,
    (v_in_credits - v_out_credits), (v_in_energy - v_out_energy), (v_in_food - v_out_food),
    (v_in_material - v_out_material), (v_in_components - v_out_components), (v_in_compute - v_out_compute),
    v_now
  )
  ON CONFLICT (owner_id) DO UPDATE
  SET
    status = 'clean',
    profile_version = daily_settlement_profiles.profile_version + 1,
    effective_game_day = v_game_day,
    credits_delta = (v_in_credits - v_out_credits),
    energy_delta = (v_in_energy - v_out_energy),
    food_delta = (v_in_food - v_out_food),
    materials_delta = (v_in_material - v_out_material),
    components_delta = (v_in_components - v_out_components),
    compute_delta = (v_in_compute - v_out_compute),
    updated_at = v_now;

  RETURN QUERY
  SELECT
    p_owner_id,
    v_game_day,
    v_game_minute,
    v_now,
    p_trigger_event,
    p_trigger_entity_id,
    h.resource,
    h.gross_inflow,
    h.gross_outflow,
    h.net_daily_rate
  FROM resource_rate_history h
  WHERE h.owner_id = p_owner_id AND h.created_at = v_now;
END;
$$;
