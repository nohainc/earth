-- Economy V2 Plan 6: authoritative balance-posting boundaries.
-- Application code must use these functions instead of updating
-- economic_accounts directly. The settlement function is deliberately
-- set-based and never calls the interactive function once per effect.

CREATE OR REPLACE FUNCTION earth_post_transaction(
  p_correlation_id TEXT,
  p_game_day BIGINT,
  p_game_minute SMALLINT,
  p_transaction_kind TEXT,
  p_source_type TEXT,
  p_source_id TEXT,
  p_rules_version TEXT,
  p_entries JSONB
)
RETURNS TABLE (
  transaction_id BIGINT,
  created BOOLEAN,
  entry_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  transaction_created BOOLEAN;
  requested_count BIGINT;
  missing_count BIGINT;
  invalid_count BIGINT;
  v_transaction_id BIGINT;
BEGIN
  IF jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) < 2 THEN
    RAISE EXCEPTION 'Interactive economic transactions require at least two entries';
  END IF;

  SELECT b.transaction_id, b.created
  INTO v_transaction_id, transaction_created
  FROM earth_begin_economic_transaction(
    p_correlation_id, p_game_day, p_game_minute, p_transaction_kind,
    p_source_type, p_source_id, p_rules_version
  ) b;
  created := transaction_created;

  IF NOT transaction_created THEN
    transaction_id := v_transaction_id;
    SELECT COUNT(*) INTO entry_count FROM economic_entries WHERE economic_entries.transaction_id = v_transaction_id;
    RETURN NEXT;
    RETURN;
  END IF;

  WITH requested AS (
    SELECT (item->>'account_id')::BIGINT AS account_id,
           SUM((item->>'delta')::BIGINT) AS delta
    FROM jsonb_array_elements(p_entries) item
    GROUP BY (item->>'account_id')::BIGINT
  )
  SELECT COUNT(*) INTO requested_count FROM requested;

  SELECT COUNT(*) INTO missing_count
  FROM (
    SELECT r.account_id
    FROM jsonb_array_elements(p_entries) item
    CROSS JOIN LATERAL (SELECT (item->>'account_id')::BIGINT AS account_id) r
    GROUP BY r.account_id
  ) requested
  LEFT JOIN economic_accounts a ON a.id = requested.account_id
  WHERE a.id IS NULL;
  IF missing_count > 0 THEN
    RAISE EXCEPTION 'Interactive economic transaction references % missing accounts', missing_count;
  END IF;

  -- Lock the complete account set in ascending ID order before validating or
  -- changing balances. This is the deadlock-avoidance rule for hot-path posts.
  PERFORM 1
  FROM economic_accounts a
  JOIN (
    SELECT DISTINCT (item->>'account_id')::BIGINT AS account_id
    FROM jsonb_array_elements(p_entries) item
  ) requested ON requested.account_id = a.id
  ORDER BY a.id
  FOR UPDATE;

  WITH requested AS (
    SELECT (item->>'account_id')::BIGINT AS account_id,
           SUM((item->>'delta')::BIGINT) AS delta
    FROM jsonb_array_elements(p_entries) item
    GROUP BY (item->>'account_id')::BIGINT
  )
  SELECT COUNT(*) INTO invalid_count
  FROM requested r
  JOIN economic_accounts a ON a.id = r.account_id
  WHERE a.status <> 'active' OR a.balance + r.delta < 0;
  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Interactive economic transaction has % invalid or insufficient account balances', invalid_count;
  END IF;

  WITH requested AS (
    SELECT (item->>'account_id')::BIGINT AS account_id,
           SUM((item->>'delta')::BIGINT) AS delta
    FROM jsonb_array_elements(p_entries) item
    GROUP BY (item->>'account_id')::BIGINT
  )
  UPDATE economic_accounts a
  SET balance = a.balance + requested.delta,
      updated_at = CURRENT_TIMESTAMP
  FROM requested
  WHERE a.id = requested.account_id;

  INSERT INTO economic_entries (transaction_id, account_id, game_day, delta, reason_code)
  SELECT v_transaction_id, (item->>'account_id')::BIGINT, p_game_day,
         (item->>'delta')::BIGINT, item->>'reason_code'
  FROM jsonb_array_elements(p_entries) item;

  transaction_id := v_transaction_id;
  SELECT COUNT(*) INTO entry_count FROM economic_entries WHERE economic_entries.transaction_id = v_transaction_id;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_settlement_batch(
  p_correlation_id TEXT,
  p_game_day BIGINT,
  p_game_minute SMALLINT,
  p_source_type TEXT,
  p_source_id TEXT,
  p_rules_version TEXT,
  p_effects JSONB
)
RETURNS TABLE (
  transaction_id BIGINT,
  created BOOLEAN,
  entry_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  transaction_created BOOLEAN;
  missing_count BIGINT;
  invalid_count BIGINT;
  v_transaction_id BIGINT;
BEGIN
  IF jsonb_typeof(p_effects) <> 'array' OR jsonb_array_length(p_effects) = 0 THEN
    RAISE EXCEPTION 'Settlement batch requires at least one effect';
  END IF;

  SELECT b.transaction_id, b.created
  INTO v_transaction_id, transaction_created
  FROM earth_begin_economic_transaction(
    p_correlation_id, p_game_day, p_game_minute, 'settlement_batch',
    p_source_type, p_source_id, p_rules_version
  ) b;
  created := transaction_created;

  IF NOT transaction_created THEN
    transaction_id := v_transaction_id;
    SELECT COUNT(*) INTO entry_count FROM economic_entries WHERE economic_entries.transaction_id = v_transaction_id;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT COUNT(*) INTO missing_count
  FROM (
    SELECT DISTINCT (item->>'account_id')::BIGINT AS account_id
    FROM jsonb_array_elements(p_effects) item
  ) requested
  LEFT JOIN economic_accounts a ON a.id = requested.account_id
  WHERE a.id IS NULL;
  IF missing_count > 0 THEN
    RAISE EXCEPTION 'Settlement batch references % missing accounts', missing_count;
  END IF;

  PERFORM 1
  FROM economic_accounts a
  JOIN (
    SELECT DISTINCT (item->>'account_id')::BIGINT AS account_id
    FROM jsonb_array_elements(p_effects) item
  ) requested ON requested.account_id = a.id
  ORDER BY a.id
  FOR UPDATE;

  WITH requested AS (
    SELECT (item->>'account_id')::BIGINT AS account_id,
           SUM((item->>'delta')::BIGINT) AS delta
    FROM jsonb_array_elements(p_effects) item
    GROUP BY (item->>'account_id')::BIGINT
  )
  SELECT COUNT(*) INTO invalid_count
  FROM requested r
  JOIN economic_accounts a ON a.id = r.account_id
  WHERE a.status <> 'active' OR a.balance + r.delta < 0;
  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Settlement batch has % invalid or insufficient account balances', invalid_count;
  END IF;

  WITH requested AS (
    SELECT (item->>'account_id')::BIGINT AS account_id,
           SUM((item->>'delta')::BIGINT) AS delta
    FROM jsonb_array_elements(p_effects) item
    GROUP BY (item->>'account_id')::BIGINT
  )
  UPDATE economic_accounts a
  SET balance = a.balance + requested.delta,
      updated_at = CURRENT_TIMESTAMP
  FROM requested
  WHERE a.id = requested.account_id;

  INSERT INTO economic_entries (transaction_id, account_id, game_day, delta, reason_code)
  SELECT v_transaction_id, (item->>'account_id')::BIGINT, p_game_day,
         (item->>'delta')::BIGINT, item->>'reason_code'
  FROM jsonb_array_elements(p_effects) item;

  transaction_id := v_transaction_id;
  SELECT COUNT(*) INTO entry_count FROM economic_entries WHERE economic_entries.transaction_id = v_transaction_id;
  RETURN NEXT;
END;
$$;
