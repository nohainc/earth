-- Final baseline database logic only. Compatibility transfer functions are excluded.

CREATE OR REPLACE FUNCTION earth_begin_economic_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO economic_transactions(correlation_id, game_day, game_minute, transaction_kind, source_type, source_id, rules_version)
  VALUES (p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version)
  ON CONFLICT (correlation_id) DO UPDATE SET correlation_id = EXCLUDED.correlation_id
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT, p_entries JSONB
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT; v_entry JSONB;
BEGIN
  v_id := earth_begin_economic_transaction(p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version);
  IF EXISTS (SELECT 1 FROM economic_entries WHERE transaction_id = v_id) THEN RETURN v_id; END IF;
  IF COALESCE(jsonb_array_length(p_entries), 0) = 0 THEN RAISE EXCEPTION 'economic transaction must contain entries'; END IF;
  IF (SELECT COALESCE(SUM((value->>'delta_units')::BIGINT), 0) FROM jsonb_array_elements(p_entries)) <> 0 THEN
    RAISE EXCEPTION 'economic transaction entries are not balanced';
  END IF;
  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    INSERT INTO economic_entries(transaction_id, account_id, delta_units, asset_id)
    VALUES (v_id, (v_entry->>'account_id')::BIGINT, (v_entry->>'delta_units')::BIGINT, (v_entry->>'asset_id')::INTEGER);
    UPDATE economic_accounts SET balance_units = balance_units + (v_entry->>'delta_units')::BIGINT WHERE id = (v_entry->>'account_id')::BIGINT;
    IF EXISTS (SELECT 1 FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT AND balance_units < 0) THEN RAISE EXCEPTION 'economic account would become negative'; END IF;
  END LOOP;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_assert_baseline_integrity() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units) THEN RAISE EXCEPTION 'market order quantity invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM institution_budget_lines WHERE authorized_units < committed_units + spent_units) THEN RAISE EXCEPTION 'budget authority invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM humans h JOIN houses x ON x.current_human_id = h.id WHERE h.status <> 'ACTIVE') THEN RAISE EXCEPTION 'House current Human invariant failed'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_game_day_from_total_minutes(p_total_minutes BIGINT)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT FLOOR(p_total_minutes / 1440)::BIGINT;
$$;

CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE(game_day BIGINT, game_minute INTEGER, total_game_minutes BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT game_day, game_minute, game_day * 1440 + game_minute
    FROM world_state WHERE id = 'WORLD';
$$;

CREATE OR REPLACE FUNCTION earth_post_settlement_batch(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_source_type TEXT, p_source_id TEXT, p_rules_version TEXT, p_effects JSONB
) RETURNS TABLE(transaction_id BIGINT, created BOOLEAN)
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  v_id := earth_post_transaction(p_correlation_id, p_game_day, p_game_minute, 'SETTLEMENT', p_source_type, p_source_id, p_rules_version, p_effects);
  RETURN QUERY SELECT v_id, TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'negative_economic_balances', COUNT(*) FROM economic_accounts WHERE balance_units < 0
  UNION ALL SELECT 'invalid_house_current_human', COUNT(*) FROM houses h JOIN humans x ON x.id = h.current_human_id WHERE x.status <> 'ACTIVE'
  UNION ALL SELECT 'invalid_market_orders', COUNT(*) FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units
  UNION ALL SELECT 'invalid_budget_authority', COUNT(*) FROM institution_budget_lines WHERE authorized_units < committed_units + spent_units;
$$;

CREATE OR REPLACE FUNCTION earth_market_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'invalid_market_orders', COUNT(*) FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units;
$$;
