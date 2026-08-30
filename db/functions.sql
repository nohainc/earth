-- EARTH PostgreSQL Stored Functions & Triggers Bundle
--
-- Authoritative definitions for stored procedures, transactional primitives,
-- cosmic time calculations, and server-side economic settlement.
--
-- Run with: psql "" -f db/functions.sql

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_catchup_owner_settlement.sql
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_create_market_order.sql
-- -----------------------------------------------------------------------------

-- Stored Function: earth_create_market_order
--
-- Authoritative server-side market order creation: catches up the player,
-- verifies and escrows funds/commodities atomically in PostgreSQL,
-- with full audit entries in resource_ledger_entries.
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

  SELECT t.game_day, t.game_minute INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;
  v_game_day := COALESCE(v_game_day, 1);
  v_game_minute := COALESCE(v_game_minute, 0);

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

    v_new_resource_bal := v_resource_balance - p_quantity;

    -- Escrow resources from inventory
    UPDATE resource_balances
    SET amount = v_new_resource_bal
    WHERE owner_id = p_human_id AND resource = p_product;

    -- Log resource deduction in ledger
    INSERT INTO resource_ledger_entries (
      id, game_day, game_minute, owner_id, resource, delta, balance_after, reason_type, reason_id, correlation_id, created_at
    ) VALUES (
      gen_random_uuid(), v_game_day, v_game_minute, p_human_id, p_product, -p_quantity, v_new_resource_bal, 'market_sell_escrow', p_order_id::TEXT, p_correlation_id, NOW()
    ) ON CONFLICT (correlation_id) DO NOTHING;

  ELSE
    RAISE EXCEPTION 'Invalid order side: %', p_side;
  END IF;

  -- 4. Place order into book
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

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_get_current_game_time.sql
-- -----------------------------------------------------------------------------

-- Stored Function: earth_get_current_game_time
--
-- Calculates the authoritative game day and minute based on real elapsed time
-- since genesis_at (24 real minutes = 1,440 real seconds = 1 game day/month cycle).
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
-- Source: db/functions/earth_mutate_resource_balance.sql
-- -----------------------------------------------------------------------------

-- Stored Function: earth_mutate_resource_balance
--
-- Authoritative atomic mutation of resource balances with mandatory
-- append-only audit logging in resource_ledger_entries.
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
  -- Input Validation
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

  -- Determine current game time if day is omitted
  IF p_game_day IS NULL THEN
    SELECT t.game_day, t.game_minute INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;
    v_game_day := COALESCE(v_game_day, 1);
    v_game_minute := COALESCE(v_game_minute, 0);
  ELSE
    v_game_day := p_game_day;
    v_game_minute := COALESCE(p_game_minute, 0);
  END IF;

  -- Idempotency Check
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

  -- Lock resource balance row (or insert default 0)
  INSERT INTO resource_balances (owner_id, resource, amount)
  VALUES (p_owner_id, p_resource, 0.0)
  ON CONFLICT (owner_id, resource) DO NOTHING;

  SELECT amount INTO v_current_balance
  FROM resource_balances
  WHERE resource_balances.owner_id = p_owner_id AND resource_balances.resource = p_resource
  FOR UPDATE;

  v_new_balance := ROUND(v_current_balance + p_delta, 6);

  -- Overdraft protection
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Insufficient resource % balance for owner %. Available: %, Requested: %',
      p_resource, p_owner_id, v_current_balance, (-p_delta);
  END IF;

  -- Update live balance
  UPDATE resource_balances
  SET amount = v_new_balance
  WHERE resource_balances.owner_id = p_owner_id AND resource_balances.resource = p_resource;

  -- Write append-only ledger entry
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

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_rebuild_settlement_profile.sql
-- -----------------------------------------------------------------------------

-- Stored Function: earth_rebuild_settlement_profile
--
-- Authoritative server-side profile builder: aggregates active building outputs
-- and upkeeps into clean daily deltas in daily_settlement_profiles.
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
#variable_conflict use_column
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
      owner_id, owner_kind, status, profile_version,
      effective_game_day, last_settled_game_day,
      energy_delta, food_delta, materials_delta, components_delta, compute_delta,
      updated_at
    ) VALUES (
      p_owner_id, 'human', 'clean', 1,
      v_game_day, v_game_day,
      0, 0, 0, 0, 0,
      NOW()
    )
    ON CONFLICT (owner_id) DO NOTHING;

    v_owner_kind := 'human';
  END IF;

  -- Iterate through active buildings owned by this entity
  FOR v_b IN
    SELECT
      b.resource_output_type,
      b.resource_output_amount,
      b.upkeep_energy,
      b.upkeep_food,
      b.upkeep_materials,
      b.upkeep_components,
      b.upkeep_compute,
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
    ELSIF v_b.resource_output_type IN ('material', 'materials') THEN
      v_materials_delta := v_materials_delta + v_out_amount;
    ELSIF v_b.resource_output_type = 'components' THEN
      v_components_delta := v_components_delta + v_out_amount;
    ELSIF v_b.resource_output_type = 'compute' THEN
      v_compute_delta := v_compute_delta + v_out_amount;
    END IF;

    -- Upkeep subtraction
    v_energy_delta := v_energy_delta - (COALESCE(v_b.upkeep_energy, 0) * v_cost_mult * v_cond_cost);
    v_food_delta := v_food_delta - (COALESCE(v_b.upkeep_food, 0) * v_cost_mult * v_cond_cost);
    v_materials_delta := v_materials_delta - (COALESCE(v_b.upkeep_materials, 0) * v_cost_mult * v_cond_cost);
    v_components_delta := v_components_delta - (COALESCE(v_b.upkeep_components, 0) * v_cost_mult * v_cond_cost);
    v_compute_delta := v_compute_delta - (COALESCE(v_b.upkeep_compute, 0) * v_cost_mult * v_cond_cost);
  END LOOP;

  -- Update daily_settlement_profiles
  UPDATE daily_settlement_profiles
  SET
    status = 'clean',
    profile_version = daily_settlement_profiles.profile_version + 1,
    effective_game_day = v_game_day,
    energy_delta = ROUND(v_energy_delta, 2),
    food_delta = ROUND(v_food_delta, 2),
    materials_delta = ROUND(v_materials_delta, 2),
    components_delta = ROUND(v_components_delta, 2),
    compute_delta = ROUND(v_compute_delta, 2),
    updated_at = NOW()
  WHERE daily_settlement_profiles.owner_id = p_owner_id;

  RETURN QUERY
  SELECT
    p.owner_id,
    p.profile_version::INTEGER,
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
-- Source: db/functions/earth_record_rate_change.sql
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Source: db/functions/earth_transfer_credits.sql
-- -----------------------------------------------------------------------------

-- Stored Function: earth_transfer_credits
--
-- Narrow financial primitive: keeps balance mutations and their ledger audit
-- entry atomic in a single PostgreSQL transaction.
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
#variable_conflict use_column
DECLARE
  v_account_count INTEGER;
  v_debit_balance NUMERIC(20,2);
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

  -- Lock both accounts
  PERFORM 1
  FROM account_balances
  WHERE account_id IN (p_debit_account, p_credit_account)
  FOR UPDATE;

  GET DIAGNOSTICS v_account_count = ROW_COUNT;

  IF v_account_count <> 2 THEN
    RAISE EXCEPTION 'Both debit and credit accounts must exist';
  END IF;

  SELECT balance
  INTO v_debit_balance
  FROM account_balances
  WHERE account_id = p_debit_account;

  IF v_debit_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient funds in debit account';
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
    reason_type,
    reason_id,
    rule_version,
    correlation_id,
    created_at
  ) VALUES (
    COALESCE(p_ledger_id, gen_random_uuid()),
    p_game_day,
    p_debit_account,
    p_credit_account,
    p_amount,
    p_reason_type,
    p_reason_id,
    p_rule_version,
    p_correlation_id,
    NOW()
  );

  RETURN QUERY
  SELECT
    'success'::TEXT,
    COALESCE(p_ledger_id, gen_random_uuid()),
    p_amount,
    FALSE;
END;
$$;
