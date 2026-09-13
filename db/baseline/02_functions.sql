-- Final baseline database logic only. Compatibility transfer functions are excluded.

CREATE OR REPLACE FUNCTION earth_settlement_watermark(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE SQL STABLE AS $$
  SELECT COALESCE(MAX(game_day) FILTER (WHERE status IN ('completed', 'baseline')), 0)::BIGINT
    FROM daily_settlement_runs
   WHERE game_day <= p_game_day;
$$;

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
  IF (SELECT COALESCE(SUM((value->>'delta_units')::BIGINT), 0) FROM jsonb_array_elements(p_entries)) <> 0
     AND p_source_type <> 'SYSTEM_ISSUANCE' THEN
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

-- Starter packages are the only player-facing issuance in the baseline. They
-- are explicit, auditable and idempotent; ordinary transfers remain balanced.
CREATE OR REPLACE FUNCTION earth_issue_starter_package(
  p_correlation_id TEXT, p_game_day BIGINT, p_house_economic_id TEXT,
  p_asset_id INTEGER, p_amount_units BIGINT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_account BIGINT; v_tx BIGINT;
BEGIN
  IF p_amount_units <= 0 THEN RAISE EXCEPTION 'starter issuance amount must be positive'; END IF;
  SELECT id INTO v_account FROM economic_accounts
   WHERE owner_economic_id = p_house_economic_id AND asset_id = p_asset_id
     AND account_type = CASE WHEN p_asset_id = 1 THEN 'WALLET' ELSE 'INVENTORY' END
     AND status = 'ACTIVE' FOR UPDATE;
  IF v_account IS NULL THEN RAISE EXCEPTION 'starter account is not provisioned'; END IF;
  v_tx := earth_post_transaction(
    p_correlation_id, p_game_day, 0, 'STARTER_ISSUANCE', 'SYSTEM_ISSUANCE',
    p_house_economic_id, 'starter-package-v1',
    jsonb_build_array(jsonb_build_object(
      'account_id', v_account, 'asset_id', p_asset_id, 'delta_units', p_amount_units
    ))
  );
  RETURN v_tx;
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

CREATE OR REPLACE FUNCTION earth_advance_world_clock(p_minutes INTEGER)
RETURNS TABLE(game_day BIGINT, game_minute INTEGER, advanced_minutes INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
  IF p_minutes IS NULL OR p_minutes < 1 OR p_minutes > 1440 THEN
    RAISE EXCEPTION 'World advancement must be between 1 and 1,440 game minutes';
  END IF;
  RETURN QUERY
  UPDATE world_state
     SET game_day = world_state.game_day + ((world_state.game_minute + p_minutes) / 1440),
         game_minute = (world_state.game_minute + p_minutes) % 1440
   WHERE world_state.id = 'WORLD'
   RETURNING world_state.game_day, world_state.game_minute, p_minutes;
END;
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

-- Tax amendments are serialized by rule lineage and always close the
-- previous open interval before the successor becomes effective.
CREATE OR REPLACE FUNCTION earth_create_tax_rule_version(
  p_tax_rule_id TEXT,
  p_scope TEXT,
  p_category TEXT,
  p_rate_bps INTEGER,
  p_tax_base_definition TEXT,
  p_beneficiary_economic_id TEXT,
  p_effective_from_game_day BIGINT,
  p_authorization_proposal_id TEXT
) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  v_version INTEGER;
  v_id TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_tax_rule_id, 0));
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_version
    FROM tax_rule_versions
   WHERE tax_rule_id = p_tax_rule_id;
  UPDATE tax_rule_versions
     SET effective_to_game_day = p_effective_from_game_day - 1
   WHERE tax_rule_id = p_tax_rule_id
     AND effective_to_game_day IS NULL;
  v_id := p_tax_rule_id || '-V' || v_version::TEXT;
  INSERT INTO tax_rule_versions (
    id, tax_rule_id, scope, category, version, effective_from_game_day,
    rate_bps, tax_base_definition, beneficiary_economic_id, authorization_proposal_id
  ) VALUES (
    v_id, p_tax_rule_id, p_scope, p_category, v_version, p_effective_from_game_day,
    p_rate_bps, p_tax_base_definition, p_beneficiary_economic_id, p_authorization_proposal_id
  );
  RETURN v_id;
END;
$$;
-- Technology/IP V2 functions.
CREATE OR REPLACE FUNCTION earth_technology_is_patentable(p_technology_id TEXT)
RETURNS BOOLEAN LANGUAGE SQL STABLE AS $$
  SELECT COALESCE((SELECT patentable FROM technology_catalog
    WHERE id = p_technology_id OR code = p_technology_id
    ORDER BY effective_from_game_day DESC, definition_version DESC LIMIT 1), FALSE);
$$;

CREATE OR REPLACE FUNCTION earth_resolve_corporation_technology_access(
  p_corporation_economic_id TEXT, p_technology_id TEXT, p_game_day BIGINT
) RETURNS TABLE(has_access BOOLEAN, access_reason TEXT, source_id TEXT)
LANGUAGE SQL STABLE AS $$
  SELECT TRUE, a.access_source, a.source_id
  FROM corporation_technology_access a
  WHERE a.corporation_economic_id = p_corporation_economic_id
    AND a.technology_id = p_technology_id AND a.status = 'ACTIVE'
    AND a.effective_from_game_day <= p_game_day
    AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
  ORDER BY CASE a.access_source WHEN 'RESEARCHED' THEN 1 WHEN 'LICENSED' THEN 2 ELSE 3 END
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION earth_assert_technology_research_allowed(p_technology_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM technology_catalog WHERE id = p_technology_id AND status = 'ACTIVE' AND effective_from_game_day <= p_game_day AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)) THEN
    RAISE EXCEPTION 'Technology catalog entry is not active for research';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_assert_technology_prerequisites_met(p_corporation_economic_id TEXT, p_technology_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_corporation_economic_id IS NULL OR p_technology_id IS NULL OR p_game_day < 0 THEN
    RAISE EXCEPTION 'Invalid technology research prerequisites';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_corporation_technology_access(
  p_corporation_economic_id TEXT, p_technology_id TEXT, p_access_source TEXT,
  p_source_id TEXT, p_effective_from_game_day BIGINT, p_effective_to_game_day BIGINT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_access_source NOT IN ('RESEARCHED','LICENSED','GRANTED') THEN RAISE EXCEPTION 'Invalid technology access source'; END IF;
  INSERT INTO corporation_technology_access (corporation_economic_id, technology_id, access_source, source_id, effective_from_game_day, effective_to_game_day, status)
  VALUES (p_corporation_economic_id, p_technology_id, p_access_source, p_source_id, p_effective_from_game_day, p_effective_to_game_day, 'ACTIVE')
  ON CONFLICT (corporation_economic_id, technology_id) DO UPDATE SET access_source = EXCLUDED.access_source, source_id = EXCLUDED.source_id, effective_from_game_day = EXCLUDED.effective_from_game_day, effective_to_game_day = EXCLUDED.effective_to_game_day, status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_completed_technology_patents(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE technology_patents SET status = 'EXPIRED' WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;
  INSERT INTO technology_patents (id, technology_id, owner_economic_id, granted_game_day, exclusive_through_game_day, status, granting_project_id)
  SELECT 'PATENT-' || p.target_id || '-' || p.id, p.target_id, p.corporation_economic_id, p.completed_game_day,
    p.completed_game_day + t.patent_exclusivity_days - 1, 'ACTIVE', p.id
  FROM corporation_research_projects p JOIN technology_catalog t ON t.id = p.target_id
  WHERE p.target_type = 'TECHNOLOGY' AND p.status = 'COMPLETED' AND p.completed_game_day = p_game_day
    AND t.patentable AND t.patent_exclusivity_days > 0 AND NOT EXISTS (SELECT 1 FROM technology_patents x WHERE x.technology_id = p.target_id AND x.status = 'ACTIVE')
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_finalize_technology_public_domain(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE technology_patents SET status = 'EXPIRED' WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;
  INSERT INTO technology_public_domain (technology_id, effective_from_game_day, source_patent_id)
  SELECT p.technology_id, p.exclusive_through_game_day + 1, p.id FROM technology_patents p
  WHERE p.status = 'EXPIRED' AND p.exclusive_through_game_day < p_game_day ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
