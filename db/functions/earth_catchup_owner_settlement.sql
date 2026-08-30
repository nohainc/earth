-- Stored Function: earth_catchup_owner_settlement
--
-- Authoritative server-side catch-up: brings an owner's balances up to date
-- from their last settled game day to the target game day in one atomic transaction,
-- writing durable audit records to resource_ledger_entries.
CREATE OR REPLACE FUNCTION earth_catchup_owner_settlement(
  p_owner_id TEXT,
  p_target_day BIGINT DEFAULT NULL
)
RETURNS TABLE (
  owner_id TEXT,
  elapsed_days INTEGER,
  last_settled_day BIGINT,
  settled BOOLEAN
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  v_target_day BIGINT;
  v_last_settled BIGINT;
  v_elapsed INTEGER;
  v_profile RECORD;
  v_energy_change NUMERIC(20,6);
  v_food_change NUMERIC(20,6);
  v_mat_change NUMERIC(20,6);
  v_comp_change NUMERIC(20,6);
  v_compute_change NUMERIC(20,6);
  v_new_bal NUMERIC(20,6);
BEGIN
  -- Determine target game day if omitted based on current world state
  IF p_target_day IS NULL THEN
    SELECT t.game_day INTO v_target_day FROM earth_get_current_game_time() t;
    v_target_day := COALESCE(v_target_day, 1);
  ELSE
    v_target_day := p_target_day;
  END IF;

  -- Lock profile record
  SELECT * INTO v_profile
  FROM daily_settlement_profiles
  WHERE daily_settlement_profiles.owner_id = p_owner_id
  FOR UPDATE;

  IF NOT FOUND OR v_profile.status = 'dirty' THEN
    PERFORM earth_rebuild_settlement_profile(p_owner_id);
    SELECT * INTO v_profile
    FROM daily_settlement_profiles
    WHERE daily_settlement_profiles.owner_id = p_owner_id
    FOR UPDATE;
  END IF;

  v_last_settled := COALESCE(v_profile.last_settled_game_day, v_target_day);
  v_elapsed := GREATEST(0, (v_target_day - v_last_settled))::INTEGER;

  IF v_elapsed > 0 AND v_profile.status = 'clean' THEN
    v_energy_change := v_profile.energy_delta * v_elapsed;
    v_food_change := v_profile.food_delta * v_elapsed;
    v_mat_change := v_profile.materials_delta * v_elapsed;
    v_comp_change := v_profile.components_delta * v_elapsed;
    v_compute_change := v_profile.compute_delta * v_elapsed;

    -- Apply Energy Delta
    IF v_energy_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'energy', GREATEST(0, v_energy_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_energy_change)
      RETURNING amount INTO v_new_bal;

      INSERT INTO resource_ledger_entries (
        id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
      ) VALUES (
        gen_random_uuid(), v_target_day, 0, p_owner_id, 'energy', v_energy_change, v_new_bal, 'daily_settlement', v_profile.profile_version::TEXT, 'settle-energy-' || p_owner_id || '-' || v_target_day::TEXT, NOW()
      ) ON CONFLICT (correlation_id) DO NOTHING;
    END IF;

    -- Apply Food Delta
    IF v_food_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'food', GREATEST(0, v_food_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_food_change)
      RETURNING amount INTO v_new_bal;

      INSERT INTO resource_ledger_entries (
        id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
      ) VALUES (
        gen_random_uuid(), v_target_day, 0, p_owner_id, 'food', v_food_change, v_new_bal, 'daily_settlement', v_profile.profile_version::TEXT, 'settle-food-' || p_owner_id || '-' || v_target_day::TEXT, NOW()
      ) ON CONFLICT (correlation_id) DO NOTHING;
    END IF;

    -- Apply Material Delta
    IF v_mat_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'material', GREATEST(0, v_mat_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_mat_change)
      RETURNING amount INTO v_new_bal;

      INSERT INTO resource_ledger_entries (
        id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
      ) VALUES (
        gen_random_uuid(), v_target_day, 0, p_owner_id, 'material', v_mat_change, v_new_bal, 'daily_settlement', v_profile.profile_version::TEXT, 'settle-mat-' || p_owner_id || '-' || v_target_day::TEXT, NOW()
      ) ON CONFLICT (correlation_id) DO NOTHING;
    END IF;

    -- Apply Components Delta
    IF v_comp_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'components', GREATEST(0, v_comp_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_comp_change)
      RETURNING amount INTO v_new_bal;

      INSERT INTO resource_ledger_entries (
        id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
      ) VALUES (
        gen_random_uuid(), v_target_day, 0, p_owner_id, 'components', v_comp_change, v_new_bal, 'daily_settlement', v_profile.profile_version::TEXT, 'settle-comp-' || p_owner_id || '-' || v_target_day::TEXT, NOW()
      ) ON CONFLICT (correlation_id) DO NOTHING;
    END IF;

    -- Apply Compute Delta
    IF v_compute_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'compute', GREATEST(0, v_compute_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_compute_change)
      RETURNING amount INTO v_new_bal;

      INSERT INTO resource_ledger_entries (
        id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
      ) VALUES (
        gen_random_uuid(), v_target_day, 0, p_owner_id, 'compute', v_compute_change, v_new_bal, 'daily_settlement', v_profile.profile_version::TEXT, 'settle-compute-' || p_owner_id || '-' || v_target_day::TEXT, NOW()
      ) ON CONFLICT (correlation_id) DO NOTHING;
    END IF;

    -- Record profile run audit record
    INSERT INTO daily_settlement_profile_runs (
      owner_id, game_day, profile_version, last_settled_game_day,
      elapsed_days, mode, expected_delta, created_at
    ) VALUES (
      p_owner_id,
      v_target_day,
      v_profile.profile_version,
      v_last_settled,
      v_elapsed,
      'applied',
      jsonb_build_object(
        'energy', v_energy_change,
        'food', v_food_change,
        'material', v_mat_change,
        'components', v_comp_change,
        'compute', v_compute_change,
        'elapsed_days', v_elapsed
      ),
      NOW()
    )
    ON CONFLICT (owner_id, game_day) DO UPDATE
      SET mode = 'applied', expected_delta = EXCLUDED.expected_delta;

    UPDATE daily_settlement_profiles
    SET
      last_settled_game_day = v_target_day,
      updated_at = NOW()
    WHERE daily_settlement_profiles.owner_id = p_owner_id;

    RETURN QUERY SELECT p_owner_id, v_elapsed, v_target_day, TRUE;
  ELSE
    RETURN QUERY SELECT p_owner_id, v_elapsed, v_last_settled, FALSE;
  END IF;
END;
$$;
