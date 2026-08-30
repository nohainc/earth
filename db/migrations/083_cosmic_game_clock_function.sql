-- Migration 083: Cosmic game clock function and date-driven catch-up
--
-- Authoritative calculation of cosmic game time from genesis_at (24 real mins = 1 game day)
-- and updates to settlement catch-up and profile recalculation.

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_get_current_game_time.sql
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (
  game_day BIGINT,
  game_minute INTEGER,
  genesis_at TIMESTAMPTZ,
  elapsed_real_seconds NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_genesis TIMESTAMPTZ;
  v_offset BIGINT;
  v_elapsed_sec NUMERIC;
  v_day BIGINT;
  v_minute INTEGER;
BEGIN
  SELECT
    COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::TIMESTAMPTZ),
    COALESCE(w.simulated_day_offset, 0)
  INTO v_genesis, v_offset
  FROM world_state w
  WHERE w.id = 'WORLD';

  IF NOT FOUND THEN
    v_genesis := '2026-01-01T00:00:00Z'::TIMESTAMPTZ;
    v_offset := 0;
  END IF;

  v_elapsed_sec := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_genesis)));
  -- 1 real second = 1 game minute; 1,440 real seconds (24 real minutes) = 1 game day
  v_day := 1 + FLOOR(v_elapsed_sec / 1440.0)::BIGINT + v_offset;
  v_minute := MOD(FLOOR(v_elapsed_sec)::BIGINT, 1440)::INTEGER;

  RETURN QUERY SELECT v_day, v_minute, v_genesis, v_elapsed_sec;
END;
$$;

-- -----------------------------------------------------------------------------
-- Update: db/functions/earth_catchup_owner_settlement.sql
-- -----------------------------------------------------------------------------

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
BEGIN
  -- Determine target game day if omitted based on genesis_at epoch (24 real mins = 1 game day)
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

  IF NOT FOUND THEN
    -- Initialize clean profile if absent
    INSERT INTO daily_settlement_profiles (
      id, owner_id, owner_kind, status, profile_version,
      effective_game_day, last_settled_game_day,
      energy_delta, food_delta, materials_delta, components_delta, compute_delta,
      created_at, updated_at
    ) VALUES (
      gen_random_uuid(), p_owner_id, 'human', 'clean', 1,
      v_target_day, v_target_day,
      0, 0, 0, 0, 0,
      NOW(), NOW()
    )
    RETURNING * INTO v_profile;
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
      SET amount = GREATEST(0, resource_balances.amount + v_energy_change);
    END IF;

    -- Apply Food Delta
    IF v_food_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'food', GREATEST(0, v_food_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_food_change);
    END IF;

    -- Apply Material Delta
    IF v_mat_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'material', GREATEST(0, v_mat_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_mat_change);
    END IF;

    -- Apply Components Delta
    IF v_comp_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'components', GREATEST(0, v_comp_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_comp_change);
    END IF;

    -- Apply Compute Delta
    IF v_compute_change <> 0 THEN
      INSERT INTO resource_balances (owner_id, resource, amount)
      VALUES (p_owner_id, 'compute', GREATEST(0, v_compute_change))
      ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = GREATEST(0, resource_balances.amount + v_compute_change);
    END IF;

    -- Record profile run audit record
    INSERT INTO daily_settlement_profile_runs (
      id, profile_id, game_day, burns_applied, accounts_settled, created_at
    ) VALUES (
      gen_random_uuid(),
      v_profile.id,
      v_target_day,
      jsonb_build_object(
        'energy', v_energy_change,
        'food', v_food_change,
        'material', v_mat_change,
        'components', v_comp_change,
        'compute', v_compute_change,
        'elapsed_days', v_elapsed
      ),
      1,
      NOW()
    )
    ON CONFLICT (game_day) DO NOTHING;

    -- Advance last settled day
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

-- -----------------------------------------------------------------------------
-- Update: db/functions/earth_rebuild_settlement_profile.sql
-- -----------------------------------------------------------------------------

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
