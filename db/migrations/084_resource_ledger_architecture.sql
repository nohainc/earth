-- Migration 084: Hybrid Resource Ledger & Live Balance Architecture
--
-- Authoritative append-only ledger for all resource movements (energy, food,
-- material, components, compute) paired with live balance state.

CREATE TABLE IF NOT EXISTS resource_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_day BIGINT NOT NULL,
  game_minute INTEGER NOT NULL DEFAULT 0,
  owner_id TEXT NOT NULL,
  resource TEXT NOT NULL CHECK (resource IN ('material','components','energy','compute','food')),
  delta NUMERIC(20,6) NOT NULL,
  balance_after NUMERIC(20,6) NOT NULL CHECK (balance_after >= 0),
  reason_type TEXT NOT NULL,
  reason_id TEXT,
  correlation_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_resource_ledger_owner_day ON resource_ledger_entries(owner_id, game_day DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_resource_ledger_reason ON resource_ledger_entries(reason_type, reason_id);
CREATE INDEX IF NOT EXISTS idx_resource_ledger_resource_day ON resource_ledger_entries(resource, game_day DESC);

-- Stored Function: earth_mutate_resource_balance
CREATE OR REPLACE FUNCTION earth_mutate_resource_balance(
  p_game_day BIGINT,
  p_owner_id TEXT,
  p_resource TEXT,
  p_delta NUMERIC(20,6),
  p_reason_type TEXT,
  p_reason_id TEXT DEFAULT NULL,
  p_correlation_id TEXT DEFAULT NULL,
  p_game_minute INTEGER DEFAULT 0
)
RETURNS TABLE (
  status TEXT,
  ledger_id UUID,
  owner_id TEXT,
  resource TEXT,
  delta NUMERIC(20,6),
  balance_after NUMERIC(20,6),
  already_processed BOOLEAN
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  v_current_balance NUMERIC(20,6) := 0.0;
  v_new_balance NUMERIC(20,6) := 0.0;
  v_ledger_id UUID := gen_random_uuid();
  v_game_day BIGINT;
  v_game_minute INTEGER;
BEGIN
  IF p_owner_id IS NULL OR LENGTH(TRIM(p_owner_id)) = 0 THEN
    RAISE EXCEPTION 'Resource mutation requires a valid owner_id';
  END IF;

  IF p_resource NOT IN ('material','components','energy','compute','food') THEN
    RAISE EXCEPTION 'Invalid resource kind: %', p_resource;
  END IF;

  IF p_delta IS NULL OR p_delta = 0 THEN
    RAISE EXCEPTION 'Resource mutation delta cannot be null or zero';
  END IF;

  IF p_reason_type IS NULL OR LENGTH(TRIM(p_reason_type)) = 0 THEN
    RAISE EXCEPTION 'Resource mutation reason_type is required';
  END IF;

  IF p_game_day IS NULL THEN
    SELECT t.game_day, t.game_minute INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;
    v_game_day := COALESCE(v_game_day, 1);
    v_game_minute := COALESCE(v_game_minute, 0);
  ELSE
    v_game_day := p_game_day;
    v_game_minute := COALESCE(p_game_minute, 0);
  END IF;

  IF p_correlation_id IS NOT NULL AND LENGTH(TRIM(p_correlation_id)) > 0 THEN
    IF EXISTS (SELECT 1 FROM resource_ledger_entries WHERE correlation_id = p_correlation_id) THEN
      RETURN QUERY
      SELECT
        'already_processed'::TEXT,
        r.id,
        r.owner_id,
        r.resource,
        r.delta,
        r.balance_after,
        TRUE
      FROM resource_ledger_entries r
      WHERE r.correlation_id = p_correlation_id
      LIMIT 1;
      RETURN;
    END IF;
  END IF;

  INSERT INTO resource_balances (owner_id, resource, amount)
  VALUES (p_owner_id, p_resource, 0.0)
  ON CONFLICT (owner_id, resource) DO NOTHING;

  SELECT amount INTO v_current_balance
  FROM resource_balances
  WHERE resource_balances.owner_id = p_owner_id AND resource_balances.resource = p_resource
  FOR UPDATE;

  v_new_balance := ROUND(v_current_balance + p_delta, 6);

  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Insufficient resource % balance for owner %. Available: %, Requested: %',
      p_resource, p_owner_id, v_current_balance, (-p_delta);
  END IF;

  UPDATE resource_balances
  SET amount = v_new_balance
  WHERE resource_balances.owner_id = p_owner_id AND resource_balances.resource = p_resource;

  INSERT INTO resource_ledger_entries (
    id,
    game_day,
    game_minute,
    owner_id,
    resource,
    delta,
    balance_after,
    reason_type,
    reason_id,
    correlation_id,
    created_at
  ) VALUES (
    v_ledger_id,
    v_game_day,
    v_game_minute,
    p_owner_id,
    p_resource,
    p_delta,
    v_new_balance,
    p_reason_type,
    p_reason_id,
    p_correlation_id,
    NOW()
  );

  RETURN QUERY
  SELECT
    'success'::TEXT,
    v_ledger_id,
    p_owner_id,
    p_resource,
    p_delta,
    v_new_balance,
    FALSE;
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
  v_energy_change NUMERIC(20,6);
  v_food_change NUMERIC(20,6);
  v_mat_change NUMERIC(20,6);
  v_comp_change NUMERIC(20,6);
  v_compute_change NUMERIC(20,6);
  v_new_bal NUMERIC(20,6);
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

-- Stored Function: earth_create_market_order
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
#variable_conflict use_column
DECLARE
  v_total_cost NUMERIC(20,2);
  v_credit_balance NUMERIC(20,2);
  v_resource_balance NUMERIC(20,6);
  v_new_resource_bal NUMERIC(20,6);
  v_existing RECORD;
  v_game_day BIGINT;
  v_game_minute INTEGER;
BEGIN
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

  PERFORM earth_catchup_owner_settlement(p_human_id);

  SELECT t.game_day, t.game_minute INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;
  v_game_day := COALESCE(v_game_day, 1);
  v_game_minute := COALESCE(v_game_minute, 0);

  IF p_side = 'buy' THEN
    v_total_cost := p_quantity * p_limit_price;

    SELECT balance INTO v_credit_balance
    FROM account_balances
    WHERE owner_id = p_human_id AND currency = 'CREDIT'
    FOR UPDATE;

    IF v_credit_balance IS NULL OR v_credit_balance < v_total_cost THEN
      RAISE EXCEPTION 'Insufficient credits for market buy order: balance=%, required=%', COALESCE(v_credit_balance, 0), v_total_cost;
    END IF;

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

    v_new_resource_bal := v_resource_balance - p_quantity;

    UPDATE resource_balances
    SET amount = v_new_resource_bal
    WHERE owner_id = p_human_id AND resource = p_product;

    INSERT INTO resource_ledger_entries (
      id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
    ) VALUES (
      gen_random_uuid(), v_game_day, v_game_minute, p_human_id, p_product, -p_quantity, v_new_resource_bal, 'market_sell_escrow', p_order_id::TEXT, p_correlation_id, NOW()
    ) ON CONFLICT (correlation_id) DO NOTHING;

  ELSE
    RAISE EXCEPTION 'Invalid order side: %', p_side;
  END IF;

  INSERT INTO market_orders (
    id, human_id, product, quantity, limit_price, filled_quantity, status, side, correlation_id, reserved_credits, created_at
  ) VALUES (
    p_order_id,
    p_human_id,
    p_product,
    p_quantity,
    p_limit_price,
    0,
    'open',
    p_side,
    p_correlation_id,
    v_total_cost,
    NOW()
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
