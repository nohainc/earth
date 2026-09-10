-- Replace the shadow profile path with an authoritative daily posting.
-- Building revenue/operating costs are included in the profile and are skipped
-- by the building engine once the profile has been settled for this day.
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
  v_credit_delta NUMERIC(20,2);
  v_credit_change NUMERIC(20,2);
  v_account_id TEXT;
  v_account_balance NUMERIC(20,2);
  v_credit_account TEXT := 'account-ouc-treasury';
  v_delta JSONB;
BEGIN
  IF p_target_day IS NULL THEN
    SELECT earth_game_day_from_total_minutes(total_game_minutes)
      INTO v_target_day FROM earth_get_current_game_time();
  ELSE
    v_target_day := p_target_day;
  END IF;

  SELECT p.* INTO v_profile
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

  -- Taxes and levies have dedicated ledger phases. The profile posts the
  -- building/business operating net so those phases are not double-counted.
  v_credit_delta := COALESCE(v_profile.gross_credits_inflow, 0)
                  - COALESCE(v_profile.operating_credits_outflow, 0);
  v_credit_change := ROUND(v_credit_delta * v_elapsed, 2);

  IF v_credit_change <> 0 THEN
    SELECT account_id, balance INTO v_account_id, v_account_balance
    FROM account_balances
    WHERE owner_id = p_owner_id AND currency = 'CREDIT'
    FOR UPDATE;

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'Cannot settle credits: account missing for owner %', p_owner_id;
    END IF;
    IF v_credit_change < 0 AND v_account_balance + v_credit_change < 0 THEN
      RAISE EXCEPTION 'Cannot settle credits: insufficient balance for owner %', p_owner_id;
    END IF;

    UPDATE account_balances
    SET balance = balance + v_credit_change
    WHERE account_id = v_account_id;

    INSERT INTO ledger_entries (
      id, game_day, debit_account, credit_account, amount,
      reason_type, reason_id, rule_version, correlation_id, created_at
    ) VALUES (
      gen_random_uuid(), v_target_day,
      CASE WHEN v_credit_change > 0 THEN v_credit_account ELSE v_account_id END,
      CASE WHEN v_credit_change > 0 THEN v_account_id ELSE v_credit_account END,
      ABS(v_credit_change), 'daily_profile_settlement', p_owner_id,
      'daily-settlement-v3', 'PROFILE-CREDITS-' || p_owner_id || '-' || v_target_day::TEXT, NOW()
    ) ON CONFLICT (correlation_id) DO NOTHING;
  END IF;

  v_delta := jsonb_build_object(
    'credits', v_credit_change,
    'energy', v_profile.energy_delta * v_elapsed,
    'food', v_profile.food_delta * v_elapsed,
    'material', v_profile.materials_delta * v_elapsed,
    'components', v_profile.components_delta * v_elapsed,
    'compute', v_profile.compute_delta * v_elapsed
  );

  INSERT INTO resource_balances (owner_id, resource, amount)
  SELECT p_owner_id, entry.key, GREATEST(0, (entry.value::TEXT)::NUMERIC)
  FROM jsonb_each(v_delta) entry
  WHERE entry.key <> 'credits' AND (entry.value::TEXT)::NUMERIC <> 0
  ON CONFLICT (owner_id, resource) DO UPDATE
    SET amount = GREATEST(0, resource_balances.amount + EXCLUDED.amount);

  INSERT INTO daily_settlement_profile_runs (
    owner_id, game_day, profile_version, last_settled_game_day,
    elapsed_days, mode, expected_delta
  ) VALUES (
    p_owner_id, v_target_day, v_profile.profile_version,
    v_profile.last_settled_game_day, v_elapsed, 'applied', v_delta
  ) ON CONFLICT (owner_id, game_day) DO UPDATE
    SET mode = 'applied', expected_delta = EXCLUDED.expected_delta;

  UPDATE daily_settlement_profiles p
  SET last_settled_game_day = v_target_day, updated_at = CURRENT_TIMESTAMP
  WHERE p.owner_id = p_owner_id;

  RETURN QUERY SELECT p_owner_id, v_elapsed, v_target_day, TRUE;
END;
$$;
