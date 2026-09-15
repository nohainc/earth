-- EARTH ACTIVE MIGRATION: architecture and economic integrity checks

-- Bridge the pre-V4 schema before installing integrity functions. These
-- objects already exist on a fresh V4 baseline; IF NOT EXISTS keeps this
-- migration idempotent while allowing legacy production databases to move
-- forward without rewriting their applied migration history.
CREATE TABLE IF NOT EXISTS economic_account_policies (
  owner_type TEXT NOT NULL,
  account_type TEXT NOT NULL REFERENCES economic_account_types(code),
  allowed_asset_kind TEXT NOT NULL CHECK (allowed_asset_kind IN ('CREDIT', 'RESOURCE', 'ANY')),
  player_visible BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (owner_type, account_type, allowed_asset_kind)
);

CREATE TABLE IF NOT EXISTS economic_transaction_kinds (
  code TEXT PRIMARY KEY,
  semantic_class TEXT NOT NULL,
  asset_kind TEXT NOT NULL,
  description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS economic_source_types (
  code TEXT PRIMARY KEY,
  source_class TEXT NOT NULL,
  description TEXT NOT NULL
);

INSERT INTO economic_transaction_kinds (code, semantic_class, asset_kind, description) VALUES
  ('ASSET_TRANSFER', 'ASSET_TRANSFER', 'ANY', 'Balanced movement of an existing asset between accounts'),
  ('CREDIT_ISSUANCE', 'CREDIT_ISSUANCE', 'CREDIT', 'Creation of CREDIT outside existing account balances'),
  ('CREDIT_RETIREMENT', 'CREDIT_RETIREMENT', 'CREDIT', 'Destruction of CREDIT outside existing account balances'),
  ('RESOURCE_PRODUCTION', 'RESOURCE_PRODUCTION', 'RESOURCE', 'Production of a resource into an economic owner inventory'),
  ('RESOURCE_CONSUMPTION', 'RESOURCE_CONSUMPTION', 'RESOURCE', 'Consumption of a resource from an economic owner inventory'),
  ('SETTLEMENT', 'ASSET_TRANSFER', 'ANY', 'Balanced settlement posting'),
  ('MARKET_TRADE', 'ASSET_TRANSFER', 'ANY', 'Balanced market settlement'),
  ('BUILDING_CONSTRUCTION', 'ASSET_TRANSFER', 'ANY', 'Balanced construction payment'),
  ('RESEARCH_FUNDING', 'ASSET_TRANSFER', 'CREDIT', 'Balanced research funding'),
  ('SUCCESSION_COST', 'ASSET_TRANSFER', 'CREDIT', 'Balanced House succession cost')
ON CONFLICT (code) DO NOTHING;

INSERT INTO economic_source_types (code, source_class, description) VALUES
  ('SYSTEM_ISSUANCE', 'SYSTEM', 'System-authorized asset issuance'),
  ('SYSTEM_PRODUCTION', 'SYSTEM', 'System resource production sink/source'),
  ('SYSTEM_CONSUMPTION', 'SYSTEM', 'System resource consumption sink/source'),
  ('HOUSE', 'ACTOR', 'House economic action'),
  ('CORPORATION', 'ACTOR', 'Corporation economic action'),
  ('MARKET', 'MARKET', 'Market clearing action'),
  ('INTERACTIVE', 'INTERACTIVE', 'Interactive user action'),
  ('SETTLEMENT', 'SETTLEMENT', 'Daily settlement action')
ON CONFLICT (code) DO NOTHING;

INSERT INTO economic_account_policies (owner_type, account_type, allowed_asset_kind, player_visible) VALUES
  ('HOUSE', 'WALLET', 'CREDIT', TRUE),
  ('HOUSE', 'INVENTORY', 'RESOURCE', TRUE),
  ('HOUSE', 'MARKET_ESCROW', 'ANY', TRUE),
  ('CORPORATION', 'TREASURY', 'CREDIT', TRUE),
  ('CORPORATION', 'OPERATIONS', 'CREDIT', TRUE),
  ('CORPORATION', 'RESERVE', 'CREDIT', TRUE),
  ('SYSTEM', 'SYSTEM_ACCOUNT', 'ANY', FALSE)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS territories (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  name TEXT NOT NULL,
  territory_type TEXT NOT NULL DEFAULT 'PRIMARY',
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  created_game_day BIGINT NOT NULL DEFAULT 1,
  UNIQUE (id, corporation_id)
);

ALTER TABLE buildings ADD COLUMN IF NOT EXISTS territory_id TEXT;
ALTER TABLE house_affiliations ADD COLUMN IF NOT EXISTS primary_territory_id TEXT;

DO $$
BEGIN
  IF to_regclass('cities') IS NOT NULL THEN
    INSERT INTO territories (id, corporation_id, name, created_game_day)
    SELECT c.id, c.corporation_id, i.name, 1
      FROM cities c
      JOIN institutions i ON i.id = c.id
     WHERE c.corporation_id IS NOT NULL
    ON CONFLICT (id, corporation_id) DO NOTHING;

    UPDATE buildings b
       SET territory_id = b.city_id
     WHERE b.territory_id IS NULL AND b.city_id IS NOT NULL;

    UPDATE house_affiliations ha
       SET primary_territory_id = ha.city_id
     WHERE ha.primary_territory_id IS NULL AND ha.city_id IS NOT NULL;
  END IF;
END;
$$;

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

  FOR v_asset_id IN
    SELECT DISTINCT (value->>'asset_id')::INTEGER
      FROM jsonb_array_elements(p_entries)
  LOOP
    SELECT SUM((value->>'delta_units')::BIGINT)
      INTO v_asset_total
      FROM jsonb_array_elements(p_entries)
     WHERE (value->>'asset_id')::INTEGER = v_asset_id;
    IF v_semantic_class = 'ASSET_TRANSFER' AND v_asset_total <> 0 THEN RAISE EXCEPTION 'asset transfer is not balanced for asset %', v_asset_id;
    ELSIF v_semantic_class = 'CREDIT_ISSUANCE' AND v_asset_total <= 0 THEN RAISE EXCEPTION 'CREDIT issuance must create a positive CREDIT amount';
    ELSIF v_semantic_class = 'CREDIT_RETIREMENT' AND v_asset_total >= 0 THEN RAISE EXCEPTION 'CREDIT retirement must destroy a positive CREDIT amount';
    ELSIF v_semantic_class IN ('RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION') AND v_asset_total <> 0 THEN RAISE EXCEPTION 'resource production/consumption must balance against its dedicated system account';
    END IF;
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
