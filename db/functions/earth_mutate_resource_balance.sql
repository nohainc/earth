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
