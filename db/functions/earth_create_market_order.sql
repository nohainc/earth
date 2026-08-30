-- Stored Function: earth_create_market_order
--
-- Authoritative server-side market order creation: catches up the player,
-- verifies and escrows funds/commodities atomically in PostgreSQL.
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
