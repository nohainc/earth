-- Migration 085: Event-Sourced Rate-Change Timeline & Historical Catch-Up
--
-- Authoritative append-only rate-change timeline storing timestamped
-- snapshots of gross inflow, gross outflow, and net daily rates whenever an
-- entity's portfolio changes, enabling exact time-weighted interval settlements.

CREATE TABLE IF NOT EXISTS resource_rate_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  game_minute INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  trigger_event TEXT NOT NULL,
  trigger_entity_id TEXT,
  resource TEXT NOT NULL CHECK (resource IN ('credits','energy','food','material','components','compute')),
  gross_inflow NUMERIC(20,6) NOT NULL DEFAULT 0,
  gross_outflow NUMERIC(20,6) NOT NULL DEFAULT 0,
  net_daily_rate NUMERIC(20,6) NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_rate_history_owner_day ON resource_rate_history(owner_id, game_day, created_at);
CREATE INDEX IF NOT EXISTS idx_rate_history_owner_resource_day ON resource_rate_history(owner_id, resource, game_day DESC);
CREATE INDEX IF NOT EXISTS idx_rate_history_created ON resource_rate_history(created_at DESC);

-- Stored Function: earth_record_rate_change
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

-- Stored Function: earth_catchup_owner_settlement
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
  v_energy_change NUMERIC(20,6) := 0;
  v_food_change NUMERIC(20,6) := 0;
  v_mat_change NUMERIC(20,6) := 0;
  v_comp_change NUMERIC(20,6) := 0;
  v_compute_change NUMERIC(20,6) := 0;
  v_credits_change NUMERIC(20,6) := 0;
  v_new_bal NUMERIC(20,6);
  v_account_id TEXT;
  v_new_credit_bal NUMERIC(20,2);
  v_interval_count INTEGER := 0;
BEGIN
  IF p_target_day IS NULL THEN
    SELECT t.game_day INTO v_target_day FROM earth_get_current_game_time() t;
    v_target_day := COALESCE(v_target_day, 1);
  ELSE
    v_target_day := p_target_day;
  END IF;

  SELECT * INTO v_profile
  FROM daily_settlement_profiles
  WHERE daily_settlement_profiles.owner_id = p_owner_id
  FOR UPDATE;

  IF NOT FOUND OR v_profile.status = 'dirty' THEN
    PERFORM earth_record_rate_change(p_owner_id, 'catchup_rebuild', NULL, v_target_day, 0);
    SELECT * INTO v_profile
    FROM daily_settlement_profiles
    WHERE daily_settlement_profiles.owner_id = p_owner_id
    FOR UPDATE;
  END IF;

  v_last_settled := COALESCE(v_profile.last_settled_game_day, v_target_day);
  v_elapsed := GREATEST(0, (v_target_day - v_last_settled))::INTEGER;

  IF v_elapsed > 0 AND v_profile.status = 'clean' THEN

    SELECT COUNT(*) INTO v_interval_count
    FROM resource_rate_history h
    WHERE h.owner_id = p_owner_id
      AND h.game_day > v_last_settled
      AND h.game_day < v_target_day;

    IF v_interval_count > 0 THEN
      WITH distinct_points AS (
        SELECT DISTINCT h.game_day
        FROM resource_rate_history h
        WHERE h.owner_id = p_owner_id
          AND h.game_day >= v_last_settled
          AND h.game_day <= v_target_day
        UNION
        SELECT v_last_settled
        UNION
        SELECT v_target_day
      ),
      ordered_points AS (
        SELECT game_day, LEAD(game_day) OVER (ORDER BY game_day) AS next_game_day
        FROM distinct_points
      ),
      intervals AS (
        SELECT game_day AS start_day, next_game_day AS end_day, (next_game_day - game_day)::INTEGER AS duration
        FROM ordered_points
        WHERE next_game_day IS NOT NULL AND next_game_day > game_day
      ),
      interval_rates AS (
        SELECT
          i.start_day,
          i.end_day,
          i.duration,
          r.resource,
          r.net_daily_rate
        FROM intervals i
        CROSS JOIN LATERAL (
          SELECT DISTINCT ON (h.resource)
            h.resource,
            h.net_daily_rate
          FROM resource_rate_history h
          WHERE h.owner_id = p_owner_id
            AND h.game_day <= i.start_day
          ORDER BY h.resource, h.game_day DESC, h.created_at DESC
        ) r
      )
      SELECT
        COALESCE(SUM(CASE WHEN resource = 'energy' THEN net_daily_rate * duration ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN resource = 'food' THEN net_daily_rate * duration ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN resource = 'material' THEN net_daily_rate * duration ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN resource = 'components' THEN net_daily_rate * duration ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN resource = 'compute' THEN net_daily_rate * duration ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN resource = 'credits' THEN net_daily_rate * duration ELSE 0 END), 0)
      INTO
        v_energy_change,
        v_food_change,
        v_mat_change,
        v_comp_change,
        v_compute_change,
        v_credits_change
      FROM interval_rates;

    ELSE
      v_energy_change := v_profile.energy_delta * v_elapsed;
      v_food_change := v_profile.food_delta * v_elapsed;
      v_mat_change := v_profile.materials_delta * v_elapsed;
      v_comp_change := v_profile.components_delta * v_elapsed;
      v_compute_change := v_profile.compute_delta * v_elapsed;
      v_credits_change := v_profile.credits_delta * v_elapsed;
    END IF;

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

    -- Apply Credits Delta
    IF v_credits_change <> 0 THEN
      SELECT account_id INTO v_account_id
      FROM account_balances
      WHERE owner_id = p_owner_id AND currency = 'CREDIT'
      FOR UPDATE;

      IF v_account_id IS NOT NULL THEN
        UPDATE account_balances
        SET balance = balance + ROUND(v_credits_change, 2)
        WHERE account_id = v_account_id
        RETURNING balance INTO v_new_credit_bal;

        IF NOT EXISTS (SELECT 1 FROM ledger_entries WHERE correlation_id = 'settle-credits-' || p_owner_id || '-' || v_target_day::TEXT) THEN
          INSERT INTO ledger_entries (
            id, game_day, debit_account, credit_account, amount, reason_type, reason_id, rule_version, correlation_id, created_at
          ) VALUES (
            gen_random_uuid(),
            v_target_day,
            CASE WHEN v_credits_change > 0 THEN 'account-ouc-treasury' ELSE v_account_id END,
            CASE WHEN v_credits_change > 0 THEN v_account_id ELSE 'account-ouc-treasury' END,
            ABS(ROUND(v_credits_change, 2)),
            'daily_building_income',
            v_profile.profile_version::TEXT,
            'settlement-v2',
            'settle-credits-' || p_owner_id || '-' || v_target_day::TEXT,
            NOW()
          );
        END IF;
      END IF;
    END IF;

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
        'credits', v_credits_change,
        'elapsed_days', v_elapsed,
        'intervals_used', v_interval_count
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

-- Initial Backfill of Rate Change History for all existing owners with buildings
DO $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT owner_id
    FROM buildings
    WHERE status = 'active' AND owner_id IS NOT NULL
    UNION
    SELECT DISTINCT city_id AS owner_id
    FROM buildings
    WHERE status = 'active' AND city_id IS NOT NULL
  LOOP
    PERFORM earth_record_rate_change(v_rec.owner_id, 'initial_backfill');
  END LOOP;
END;
$$;
