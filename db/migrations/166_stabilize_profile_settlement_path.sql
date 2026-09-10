-- Plan 17 P0: profile acceleration is allowed only for deterministic,
-- non-consuming physical output. Commercial revenue, civic utilities,
-- shareholder distributions, repairs, and shortage-sensitive buildings remain
-- on the detailed building settlement path.

DO $$
DECLARE
  definition_text TEXT;
  old_fragment TEXT := $old$
  v_elapsed := GREATEST(0, v_target_day - v_profile.last_settled_game_day)::INTEGER;$old$;
  new_fragment TEXT := $new$
  -- Profile acceleration is unsafe when any active building has a balance-
  -- dependent cost, credit revenue, repair behavior, or shareholder flow.
  IF EXISTS (
    SELECT 1
    FROM buildings b
    LEFT JOIN building_catalog bc ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE b.status = 'active'
      AND (
        (COALESCE(b.ownership_class, 'private') = 'civic' AND b.city_id = p_owner_id)
        OR (COALESCE(b.ownership_class, 'private') <> 'civic' AND b.owner_id = p_owner_id)
      )
      AND (
        COALESCE(b.ownership_class, 'private') = 'public_investment'
        OR b.resource_output_type = 'credits'
        OR COALESCE(bc.output_credits, 0) <> 0
        OR COALESCE(b.daily_operating_credits, 0) <> 0
        OR COALESCE(bc.operating_credits, 0) <> 0
        OR COALESCE(b.upkeep_energy, 0) <> 0 OR COALESCE(bc.upkeep_energy, 0) <> 0
        OR COALESCE(b.upkeep_food, 0) <> 0 OR COALESCE(bc.upkeep_food, 0) <> 0
        OR COALESCE(b.upkeep_materials, 0) <> 0 OR COALESCE(bc.upkeep_materials, 0) <> 0
        OR COALESCE(b.upkeep_components, 0) <> 0 OR COALESCE(bc.upkeep_components, 0) <> 0
        OR COALESCE(b.upkeep_compute, 0) <> 0 OR COALESCE(bc.upkeep_compute, 0) <> 0
        OR COALESCE(b.auto_repair_enabled, FALSE)
      )
  ) THEN
    RETURN QUERY SELECT p_owner_id, 0, v_profile.last_settled_game_day, FALSE;
    RETURN;
  END IF;

  -- The profile builder stores two-decimal compatibility deltas. Require the
  -- stored values to be exact at that precision before skipping detail.
  IF v_profile.energy_delta <> ROUND(v_profile.energy_delta, 2)
     OR v_profile.food_delta <> ROUND(v_profile.food_delta, 2)
     OR v_profile.materials_delta <> ROUND(v_profile.materials_delta, 2)
     OR v_profile.components_delta <> ROUND(v_profile.components_delta, 2)
     OR v_profile.compute_delta <> ROUND(v_profile.compute_delta, 2)
     OR COALESCE(v_profile.credits_delta, 0) <> 0
     OR COALESCE(v_profile.gross_credits_inflow, 0) <> 0
     OR COALESCE(v_profile.operating_credits_outflow, 0) <> 0
  THEN
    RETURN QUERY SELECT p_owner_id, 0, v_profile.last_settled_game_day, FALSE;
    RETURN;
  END IF;

  v_elapsed := GREATEST(0, v_target_day - v_profile.last_settled_game_day)::INTEGER;$new$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_catchup_owner_settlement'
  LIMIT 1;
  IF definition_text IS NULL OR position(old_fragment IN definition_text) = 0 THEN
    RAISE EXCEPTION 'Cannot locate current settlement cursor in earth_catchup_owner_settlement';
  END IF;
  EXECUTE replace(definition_text, old_fragment, new_fragment);
END;
$$;
