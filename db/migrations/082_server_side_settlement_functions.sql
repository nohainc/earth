-- Migration 082: DB server-side economic settlement functions
--
-- Authoritative stored functions for:
-- 1. Atomic credit transfer (earth_transfer_credits)
-- 2. Server-side settlement profile builder (earth_rebuild_settlement_profile)
-- 3. Server-side multi-day owner catch-up (earth_catchup_owner_settlement)
-- 4. Atomic market order creation and balance escrow (earth_create_market_order)

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_catchup_owner_settlement.sql
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
  -- Determine target game day if omitted
  IF p_target_day IS NULL THEN
    SELECT game_day INTO v_target_day FROM world_state WHERE id = 'WORLD';
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
-- Source: db/functions/earth_create_market_order.sql
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION earth_create_market_order(
  p_order_id UUID,
  p_human_id TEXT,
  p_product TEXT,
  p_side TEXT,
  p_quantity NUMERIC(20,6),
  p_limit_price NUMERIC(20,2),
  p_correlation_id TEXT DEFAULT NULL
)
RETURNS TABLE (
  order_id UUID,
  human_id TEXT,
  product TEXT,
  side TEXT,
  quantity NUMERIC(20,6),
  limit_price NUMERIC(20,2),
  reserved_credits NUMERIC(20,2),
  status TEXT,
  already_processed BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_cost NUMERIC(20,2);
  v_credit_balance NUMERIC(20,2);
  v_resource_balance NUMERIC(20,6);
  v_existing RECORD;
BEGIN
  -- 1. Idempotency check via correlation ID
  IF p_correlation_id IS NOT NULL THEN
    SELECT * INTO v_existing
    FROM market_orders m
    WHERE m.human_id = p_human_id AND m.correlation_id = p_correlation_id
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY SELECT
        v_existing.id,
        v_existing.human_id,
        v_existing.product,
        v_existing.side,
        v_existing.quantity,
        v_existing.limit_price,
        v_existing.reserved_credits,
        v_existing.status,
        TRUE;
      RETURN;
    END IF;
  END IF;

  -- 2. Catch up owner to current game day before trade action
  PERFORM earth_catchup_owner_settlement(p_human_id);

  -- 3. Side validation & Escrow
  IF p_side = 'buy' THEN
    v_total_cost := p_quantity * p_limit_price;

    SELECT balance INTO v_credit_balance
    FROM account_balances
    WHERE owner_id = p_human_id AND currency = 'CREDIT'
    FOR UPDATE;

    IF v_credit_balance IS NULL OR v_credit_balance < v_total_cost THEN
      RAISE EXCEPTION 'Insufficient credits for market buy order: balance=%, required=%', COALESCE(v_credit_balance, 0), v_total_cost;
    END IF;

    -- Escrow credits from liquid balance
    UPDATE account_balances
    SET balance = balance - v_total_cost
    WHERE owner_id = p_human_id AND currency = 'CREDIT';

  ELSIF p_side = 'sell' THEN
    v_total_cost := 0;

    SELECT amount INTO v_resource_balance
    FROM resource_balances
    WHERE owner_id = p_human_id AND resource = p_product
    FOR UPDATE;

    IF v_resource_balance IS NULL OR v_resource_balance < p_quantity THEN
      RAISE EXCEPTION 'Insufficient % for market sell order: balance=%, required=%', p_product, COALESCE(v_resource_balance, 0), p_quantity;
    END IF;

    -- Escrow resources from inventory
    UPDATE resource_balances
    SET amount = amount - p_quantity
    WHERE owner_id = p_human_id AND resource = p_product;

  ELSE
    RAISE EXCEPTION 'Invalid order side: %', p_side;
  END IF;

  -- 4. Place order into book
  INSERT INTO market_orders (
    id, human_id, product, quantity, limit_price, filled_quantity, status, side, correlation_id, reserved_credits, created_at
  ) VALUES (
    p_order_id, p_human_id, p_product, p_quantity, p_limit_price, 0, 'open', p_side, p_correlation_id, v_total_cost, NOW()
  );

  RETURN QUERY SELECT
    p_order_id,
    p_human_id,
    p_product,
    p_side,
    p_quantity,
    p_limit_price,
    v_total_cost,
    'open'::TEXT,
    FALSE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_rebuild_settlement_profile.sql
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
  -- Determine current game day if omitted
  IF p_game_day IS NULL THEN
    SELECT game_day INTO v_game_day FROM world_state WHERE id = 'WORLD';
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

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_transfer_credits.sql
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION earth_transfer_credits(
  p_ledger_id UUID,
  p_game_day BIGINT,
  p_debit_account TEXT,
  p_credit_account TEXT,
  p_amount NUMERIC(20,2),
  p_reason_type TEXT,
  p_reason_id TEXT,
  p_rule_version TEXT,
  p_correlation_id TEXT
)
RETURNS TABLE (
  status TEXT,
  ledger_id UUID,
  amount NUMERIC(20,2),
  already_processed BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
  account_count INTEGER;
BEGIN
  IF p_debit_account IS NULL OR p_credit_account IS NULL OR p_debit_account = p_credit_account THEN
    RAISE EXCEPTION 'Credit transfer requires two different accounts';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Credit transfer amount must be positive';
  END IF;

  IF p_reason_type IS NULL OR LENGTH(TRIM(p_reason_type)) = 0 THEN
    RAISE EXCEPTION 'Credit transfer reason type is required';
  END IF;

  IF p_correlation_id IS NULL OR LENGTH(TRIM(p_correlation_id)) = 0 THEN
    RAISE EXCEPTION 'Credit transfer correlation ID is required';
  END IF;

  IF EXISTS (SELECT 1 FROM ledger_entries WHERE correlation_id = p_correlation_id) THEN
    RETURN QUERY
    SELECT
      'already_processed'::TEXT,
      l.id,
      l.amount,
      TRUE
    FROM ledger_entries l
    WHERE l.correlation_id = p_correlation_id
    LIMIT 1;
    RETURN;
  END IF;

  SELECT COUNT(*)
  INTO account_count
  FROM account_balances
  WHERE account_id IN (p_debit_account, p_credit_account)
  FOR UPDATE;

  IF account_count < 2 THEN
    RAISE EXCEPTION 'One or both accounts missing: debit=%, credit=%', p_debit_account, p_credit_account;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM account_balances
    WHERE account_id = p_debit_account
      AND balance >= p_amount
  ) THEN
    RAISE EXCEPTION 'Insufficient funds in debit account %', p_debit_account;
  END IF;

  UPDATE account_balances
  SET balance = balance - p_amount
  WHERE account_id = p_debit_account;

  UPDATE account_balances
  SET balance = balance + p_amount
  WHERE account_id = p_credit_account;

  INSERT INTO ledger_entries (
    id,
    game_day,
    debit_account,
    credit_account,
    amount,
    currency,
    reason_type,
    reason_id,
    rule_version,
    correlation_id
  ) VALUES (
    p_ledger_id,
    p_game_day,
    p_debit_account,
    p_credit_account,
    p_amount,
    'CREDIT',
    p_reason_type,
    p_reason_id,
    COALESCE(p_rule_version, 'v0.1'),
    p_correlation_id
  );

  RETURN QUERY
  SELECT
    'applied'::TEXT,
    p_ledger_id,
    p_amount,
    FALSE;
END;
$$;
