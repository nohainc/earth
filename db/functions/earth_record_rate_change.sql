-- Stored Function: earth_record_rate_change
--
-- Authoritative server-side procedure to compute and record timestamped
-- rate change snapshots for all 6 resources whenever an owner's building
-- portfolio, policy, or active state changes.
DROP FUNCTION IF EXISTS earth_record_rate_change(TEXT, TEXT, TEXT, BIGINT, INTEGER);
DROP FUNCTION IF EXISTS earth_record_rate_change;

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
  tax_amount NUMERIC(20,6),
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

  -- Taxes
  v_tax_credits NUMERIC(20,6) := 0;
  v_basic_levy_rate NUMERIC(20,6) := 0.06;
  v_business_tax_rate NUMERIC(20,6) := 0.05;

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

  -- Fetch active tax rates from tax_rules
  SELECT COALESCE(rate, 0.06) INTO v_basic_levy_rate
  FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = true;
  v_basic_levy_rate := COALESCE(v_basic_levy_rate, 0.06);

  SELECT COALESCE(rate, 0.05) INTO v_business_tax_rate
  FROM tax_rules WHERE id = 'TAX-OUC-BUSINESS' AND active = true;
  v_business_tax_rate := COALESCE(v_business_tax_rate, 0.05);

  -- Aggregate active buildings joining building_catalog
  FOR v_b IN
    SELECT
      bc.output_credits,
      bc.output_energy,
      bc.output_food,
      bc.output_materials,
      bc.output_components,
      bc.output_compute,
      bc.upkeep_credits,
      bc.upkeep_energy,
      bc.upkeep_food,
      bc.upkeep_materials,
      bc.upkeep_components,
      bc.upkeep_compute,
      bc.operating_credits,
      bc.operating_energy,
      bc.operating_food,
      bc.operating_materials,
      bc.operating_components,
      bc.operating_compute,
      b.operating_policy,
      b.condition
    FROM buildings b
    JOIN building_catalog bc ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE (
      (v_owner_kind = 'city' AND b.city_id = p_owner_id AND (b.ownership_class = 'civic' OR bc.ownership_class = 'civic'))
      OR (v_owner_kind <> 'city' AND b.owner_id = p_owner_id AND (b.ownership_class = 'private' OR bc.ownership_class = 'private'))
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

    v_eff := v_out_mult;
    v_cond_cost := v_cost_mult;

    -- Inflows (Outputs)
    v_in_credits := v_in_credits + ROUND(COALESCE(v_b.output_credits, 0) * v_eff, 6);
    v_in_energy := v_in_energy + ROUND(COALESCE(v_b.output_energy, 0) * v_eff, 6);
    v_in_food := v_in_food + ROUND(COALESCE(v_b.output_food, 0) * v_eff, 6);
    v_in_material := v_in_material + ROUND(COALESCE(v_b.output_materials, 0) * v_eff, 6);
    v_in_components := v_in_components + ROUND(COALESCE(v_b.output_components, 0) * v_eff, 6);
    v_in_compute := v_in_compute + ROUND(COALESCE(v_b.output_compute, 0) * v_eff, 6);

    -- Outflows (Upkeep + Operating)
    v_out_credits := v_out_credits + ROUND((COALESCE(v_b.upkeep_credits, 0) + COALESCE(v_b.operating_credits, 0)) * v_cond_cost, 6);
    v_out_energy := v_out_energy + ROUND((COALESCE(v_b.upkeep_energy, 0) + COALESCE(v_b.operating_energy, 0)) * v_cond_cost, 6);
    v_out_food := v_out_food + ROUND((COALESCE(v_b.upkeep_food, 0) + COALESCE(v_b.operating_food, 0)) * v_cond_cost, 6);
    v_out_material := v_out_material + ROUND((COALESCE(v_b.upkeep_materials, 0) + COALESCE(v_b.operating_materials, 0)) * v_cond_cost, 6);
    v_out_components := v_out_components + ROUND((COALESCE(v_b.upkeep_components, 0) + COALESCE(v_b.operating_components, 0)) * v_cond_cost, 6);
    v_out_compute := v_out_compute + ROUND((COALESCE(v_b.upkeep_compute, 0) + COALESCE(v_b.operating_compute, 0)) * v_cond_cost, 6);
  END LOOP;

  -- Taxes calculation for credits (basic civic levy + business revenue tax)
  IF v_owner_kind = 'human' THEN
    v_tax_credits := ROUND((100.0 * v_basic_levy_rate) + (v_in_credits * v_business_tax_rate), 6);
  ELSIF v_owner_kind = 'corporation' THEN
    v_tax_credits := ROUND(v_in_credits * v_business_tax_rate, 6);
  ELSE
    v_tax_credits := 0;
  END IF;

  -- Insert snapshot rows for all 6 resources with full tax & net breakdown
  INSERT INTO resource_rate_history (
    id, owner_id, game_day, game_minute, created_at,
    trigger_event, trigger_entity_id, resource,
    gross_inflow, gross_outflow, tax_amount, net_daily_rate
  ) VALUES
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'credits', v_in_credits, v_out_credits, v_tax_credits, (v_in_credits - v_out_credits - v_tax_credits)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'energy', v_in_energy, v_out_energy, 0, (v_in_energy - v_out_energy)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'food', v_in_food, v_out_food, 0, (v_in_food - v_out_food)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'material', v_in_material, v_out_material, 0, (v_in_material - v_out_material)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'components', v_in_components, v_out_components, 0, (v_in_components - v_out_components)),
    (gen_random_uuid(), p_owner_id, v_game_day, v_game_minute, v_now, p_trigger_event, p_trigger_entity_id, 'compute', v_in_compute, v_out_compute, 0, (v_in_compute - v_out_compute));

  -- Also update daily_settlement_profiles with the new clean net rates and subtotal columns
  INSERT INTO daily_settlement_profiles (
    owner_id, owner_kind, status, profile_version,
    effective_game_day, last_settled_game_day,
    gross_credits_inflow, operating_credits_outflow, tax_credits_outflow,
    credits_delta, energy_delta, food_delta, materials_delta, components_delta, compute_delta,
    updated_at
  ) VALUES (
    p_owner_id, v_owner_kind, 'clean', 1,
    v_game_day, v_game_day,
    ROUND(v_in_credits, 2), ROUND(v_out_credits, 2), ROUND(v_tax_credits, 2),
    ROUND(v_in_credits - v_out_credits - v_tax_credits, 2),
    ROUND(v_in_energy - v_out_energy, 2),
    ROUND(v_in_food - v_out_food, 2),
    ROUND(v_in_material - v_out_material, 2),
    ROUND(v_in_components - v_out_components, 2),
    ROUND(v_in_compute - v_out_compute, 2),
    v_now
  )
  ON CONFLICT (owner_id) DO UPDATE
  SET
    status = 'clean',
    profile_version = daily_settlement_profiles.profile_version + 1,
    effective_game_day = v_game_day,
    gross_credits_inflow = ROUND(v_in_credits, 2),
    operating_credits_outflow = ROUND(v_out_credits, 2),
    tax_credits_outflow = ROUND(v_tax_credits, 2),
    credits_delta = ROUND(v_in_credits - v_out_credits - v_tax_credits, 2),
    energy_delta = ROUND(v_in_energy - v_out_energy, 2),
    food_delta = ROUND(v_in_food - v_out_food, 2),
    materials_delta = ROUND(v_in_material - v_out_material, 2),
    components_delta = ROUND(v_in_components - v_out_components, 2),
    compute_delta = ROUND(v_in_compute - v_out_compute, 2),
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
    h.tax_amount,
    h.net_daily_rate
  FROM resource_rate_history h
  WHERE h.owner_id = p_owner_id AND h.created_at = v_now;
END;
$$;
