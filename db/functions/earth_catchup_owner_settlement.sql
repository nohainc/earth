-- Stored Function: earth_catchup_owner_settlement
--
-- Authoritative server-side timeline catch-up: brings an owner's balances up to date
-- across all historical rate change intervals between last settled game day
-- and target game day in one atomic transaction, writing durable timestamped
-- audit records to resource_ledger_entries and financial ledger_entries.
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
  -- Determine target game day if omitted based on current cosmic game clock
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
