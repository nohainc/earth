-- EARTH ACTIVE MIGRATION: architecture and economic integrity checks

CREATE OR REPLACE FUNCTION earth_post_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT, p_entries JSONB
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_id BIGINT;
  v_entry JSONB;
  v_account_asset_id INTEGER;
  v_entry_asset_kind TEXT;
  v_semantic_class TEXT;
  v_asset_kind TEXT;
  v_asset_id INTEGER;
  v_asset_total BIGINT;
BEGIN
  v_id := earth_begin_economic_transaction(p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version);
  IF EXISTS (SELECT 1 FROM economic_entries WHERE transaction_id = v_id) THEN RETURN v_id; END IF;
  IF COALESCE(jsonb_array_length(p_entries), 0) = 0 THEN RAISE EXCEPTION 'economic transaction must contain entries'; END IF;

  SELECT COALESCE(k.semantic_class, 'ASSET_TRANSFER'), COALESCE(k.asset_kind, 'ANY')
    INTO v_semantic_class, v_asset_kind
    FROM (SELECT 1) seed
    LEFT JOIN economic_transaction_kinds k ON k.code = p_transaction_kind;

  IF v_semantic_class = 'RESOURCE_PRODUCTION' AND p_source_type <> 'SYSTEM_PRODUCTION' THEN
    RAISE EXCEPTION 'resource production requires SYSTEM_PRODUCTION authority';
  ELSIF v_semantic_class = 'RESOURCE_CONSUMPTION' AND p_source_type <> 'SYSTEM_CONSUMPTION' THEN
    RAISE EXCEPTION 'resource consumption requires SYSTEM_CONSUMPTION authority';
  ELSIF v_semantic_class = 'CREDIT_ISSUANCE' AND p_source_type <> 'SYSTEM_ISSUANCE' THEN
    RAISE EXCEPTION 'CREDIT issuance requires SYSTEM_ISSUANCE authority';
  END IF;

  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    SELECT asset_id INTO v_account_asset_id FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT;
    IF v_account_asset_id IS NULL THEN RAISE EXCEPTION 'economic transaction account does not exist: %', v_entry->>'account_id'; END IF;
    IF v_account_asset_id <> (v_entry->>'asset_id')::INTEGER THEN RAISE EXCEPTION 'economic entry asset does not match account asset'; END IF;
    SELECT asset_kind INTO v_entry_asset_kind FROM economic_assets WHERE id = (v_entry->>'asset_id')::INTEGER;
    IF v_entry_asset_kind IS NULL THEN RAISE EXCEPTION 'economic transaction asset does not exist'; END IF;
    IF v_asset_kind <> 'ANY' AND v_entry_asset_kind <> v_asset_kind THEN RAISE EXCEPTION 'transaction semantic % only accepts % assets', v_semantic_class, v_asset_kind; END IF;
  END LOOP;

  IF v_semantic_class IN ('RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION') AND NOT EXISTS (
    SELECT 1
      FROM jsonb_array_elements(p_entries) item
      JOIN economic_accounts a ON a.id = (item->>'account_id')::BIGINT AND a.account_type = 'SYSTEM_ACCOUNT'
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id AND o.owner_type = 'SYSTEM'
     WHERE CASE WHEN v_semantic_class = 'RESOURCE_PRODUCTION' THEN (item->>'delta_units')::BIGINT < 0 ELSE (item->>'delta_units')::BIGINT > 0 END
  ) THEN
    RAISE EXCEPTION '% requires its dedicated system authority account', v_semantic_class;
  END IF;

  FOR v_asset_id, v_asset_total IN
    SELECT (value->>'asset_id')::INTEGER, SUM((value->>'delta_units')::BIGINT)
      FROM jsonb_array_elements(p_entries) GROUP BY (value->>'asset_id')::INTEGER
  LOOP
    IF v_semantic_class = 'ASSET_TRANSFER' AND v_asset_total <> 0 THEN RAISE EXCEPTION 'asset transfer is not balanced for asset %', v_asset_id;
    ELSIF v_semantic_class = 'CREDIT_ISSUANCE' AND v_asset_total <= 0 THEN RAISE EXCEPTION 'CREDIT issuance must create a positive CREDIT amount';
    ELSIF v_semantic_class = 'CREDIT_RETIREMENT' AND v_asset_total >= 0 THEN RAISE EXCEPTION 'CREDIT retirement must destroy a positive CREDIT amount';
    ELSIF v_semantic_class IN ('RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION') AND v_asset_total <> 0 THEN RAISE EXCEPTION 'resource production/consumption must balance against its dedicated system account';
  END LOOP;

  IF v_semantic_class = 'CREDIT_ISSUANCE' AND EXISTS (SELECT 1 FROM jsonb_array_elements(p_entries) WHERE (value->>'delta_units')::BIGINT <= 0) THEN RAISE EXCEPTION 'CREDIT issuance entries must all be positive'; END IF;
  IF v_semantic_class = 'CREDIT_RETIREMENT' AND EXISTS (SELECT 1 FROM jsonb_array_elements(p_entries) WHERE (value->>'delta_units')::BIGINT >= 0) THEN RAISE EXCEPTION 'CREDIT retirement entries must all be negative'; END IF;

  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    INSERT INTO economic_entries(transaction_id, account_id, delta_units, asset_id)
    VALUES (v_id, (v_entry->>'account_id')::BIGINT, (v_entry->>'delta_units')::BIGINT, (v_entry->>'asset_id')::INTEGER);
    UPDATE economic_accounts SET balance_units = balance_units + (v_entry->>'delta_units')::BIGINT WHERE id = (v_entry->>'account_id')::BIGINT;
    IF EXISTS (SELECT 1 FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT AND balance_units < 0) THEN RAISE EXCEPTION 'economic account would become negative'; END IF;
  END LOOP;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'negative_economic_balances', COUNT(*) FROM economic_accounts WHERE balance_units < 0
  UNION ALL SELECT 'invalid_economic_account_capabilities', COUNT(*)
    FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id JOIN economic_assets e ON e.id = a.asset_id
   WHERE NOT EXISTS (SELECT 1 FROM economic_account_policies p WHERE p.owner_type = o.owner_type AND p.account_type = a.account_type AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY'))
  UNION ALL SELECT 'invalid_resource_inventory_owners', COUNT(*)
    FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id JOIN economic_assets e ON e.id = a.asset_id
   WHERE a.account_type = 'INVENTORY' AND e.asset_kind = 'RESOURCE' AND o.owner_type <> 'HOUSE'
  UNION ALL SELECT 'invalid_human_economic_accounts', COUNT(*) FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id JOIN humans h ON h.id = o.id
  UNION ALL SELECT 'invalid_territory_economic_accounts', COUNT(*) FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id JOIN territories t ON t.id = o.id
  UNION ALL SELECT 'invalid_building_economic_accounts', COUNT(*) FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id JOIN buildings b ON b.id = o.id
  UNION ALL SELECT 'invalid_private_building_owners', COUNT(*) FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE c.ownership_scope = 'PRIVATE' AND o.owner_type <> 'HOUSE'
  UNION ALL SELECT 'invalid_public_building_owners', COUNT(*) FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE c.ownership_scope = 'PUBLIC' AND o.owner_type <> 'CORPORATION'
  UNION ALL SELECT 'invalid_public_catalog_resources', COUNT(*) FROM building_catalog WHERE ownership_scope = 'PUBLIC' AND (resource_input_units <> '{}'::jsonb OR resource_output_units <> '{}'::jsonb OR service_type IS NULL)
  UNION ALL SELECT 'invalid_market_order_owners', COUNT(*) FROM market_orders m JOIN owner_registry o ON o.economic_id = m.owner_economic_id WHERE o.owner_type <> 'HOUSE'
  UNION ALL SELECT 'invalid_market_orders', COUNT(*) FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units
  UNION ALL SELECT 'invalid_asset_transfer_balance', COUNT(*) FROM (SELECT t.id, e.asset_id FROM economic_transactions t JOIN economic_transaction_kinds k ON k.code = t.transaction_kind JOIN economic_entries e ON e.transaction_id = t.id WHERE k.semantic_class = 'ASSET_TRANSFER' GROUP BY t.id, e.asset_id HAVING SUM(e.delta_units) <> 0) invalid
  UNION ALL SELECT 'invalid_resource_production_authority', COUNT(*) FROM economic_transactions t JOIN economic_transaction_kinds k ON k.code = t.transaction_kind WHERE k.semantic_class = 'RESOURCE_PRODUCTION' AND (t.source_type <> 'SYSTEM_PRODUCTION' OR NOT EXISTS (SELECT 1 FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE e.transaction_id = t.id AND a.account_type = 'SYSTEM_ACCOUNT' AND o.owner_type = 'SYSTEM' AND e.delta_units < 0))
  UNION ALL SELECT 'invalid_resource_consumption_authority', COUNT(*) FROM economic_transactions t JOIN economic_transaction_kinds k ON k.code = t.transaction_kind WHERE k.semantic_class = 'RESOURCE_CONSUMPTION' AND (t.source_type <> 'SYSTEM_CONSUMPTION' OR NOT EXISTS (SELECT 1 FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE e.transaction_id = t.id AND a.account_type = 'SYSTEM_ACCOUNT' AND o.owner_type = 'SYSTEM' AND e.delta_units > 0))
  UNION ALL SELECT 'invalid_credit_issuance_authority', COUNT(*) FROM economic_transactions t JOIN economic_transaction_kinds k ON k.code = t.transaction_kind WHERE k.semantic_class = 'CREDIT_ISSUANCE' AND t.source_type <> 'SYSTEM_ISSUANCE'
  UNION ALL SELECT 'invalid_house_current_human', COUNT(*) FROM houses h JOIN humans x ON x.id = h.current_human_id WHERE x.status <> 'ACTIVE'
  UNION ALL SELECT 'invalid_budget_authority', COUNT(*) FROM institution_budget_lines WHERE authorized_units < committed_units + spent_units;
$$;
