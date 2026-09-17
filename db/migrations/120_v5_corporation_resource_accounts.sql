-- EARTH ACTIVE MIGRATION: V5 Corporation Economic Accounts
-- Provisions RESOURCE Inventory accounts and MARKET_ESCROW accounts for Corporations,
-- updates earth_provision_corporation_economy, backfills existing Corporations,
-- and updates architecture integrity reporting.

-- 1. Ensure Economic Account Policies for Corporation
INSERT INTO economic_account_policies (owner_type, account_type, allowed_asset_kind, player_visible)
VALUES
  ('CORPORATION', 'TREASURY', 'CREDIT', TRUE),
  ('CORPORATION', 'OPERATIONS', 'CREDIT', TRUE),
  ('CORPORATION', 'RESERVE', 'CREDIT', TRUE),
  ('CORPORATION', 'INVENTORY', 'RESOURCE', TRUE),
  ('CORPORATION', 'MARKET_ESCROW', 'ANY', TRUE)
ON CONFLICT (owner_type, account_type, allowed_asset_kind) DO NOTHING;

-- 2. Update earth_provision_corporation_economy
CREATE OR REPLACE FUNCTION earth_provision_corporation_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'CORPORATION' THEN
    RAISE EXCEPTION 'Corporation economy provisioning requires a CORPORATION owner: %', p_economic_id;
  END IF;

  -- CREDIT Accounts: TREASURY, OPERATIONS, RESERVE
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('TREASURY'::TEXT), ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  -- RESOURCE Accounts: INVENTORY for all 5 resources
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'INVENTORY'
    FROM economic_assets
   WHERE asset_kind = 'RESOURCE'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  -- MARKET_ESCROW Accounts for CREDIT and all 5 resources
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'MARKET_ESCROW'
    FROM economic_assets
   WHERE asset_kind IN ('CREDIT', 'RESOURCE')
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id
     AND (
       (account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE') AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT'))
       OR (account_type = 'INVENTORY' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'RESOURCE'))
       OR (account_type = 'MARKET_ESCROW' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind IN ('CREDIT', 'RESOURCE')))
     );
  RETURN v_account_count;
END;
$$;

-- 2.5. Update market order validation to allow Corporations
CREATE OR REPLACE FUNCTION earth_validate_market_order_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_asset_kind TEXT;
BEGIN
  SELECT o.owner_type, a.asset_kind
    INTO v_owner_type, v_asset_kind
    FROM owner_registry o
    JOIN economic_assets a ON a.id = (SELECT asset_id FROM market_instruments WHERE id = NEW.instrument_id)
   WHERE o.economic_id = NEW.owner_economic_id;
  IF v_owner_type NOT IN ('HOUSE', 'CORPORATION') THEN
    RAISE EXCEPTION 'Market orders must be House or Corporation-owned';
  END IF;
  RETURN NEW;
END;
$$;

-- 3. Update earth_integrity_report to allow CORPORATION for resource inventory and market orders
CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'negative_economic_balances', COUNT(*)::BIGINT
    FROM economic_accounts
   WHERE balance_units < 0 AND account_type <> 'SYSTEM_ACCOUNT'
  UNION ALL
  SELECT 'invalid_economic_account_capabilities', COUNT(*)::BIGINT
    FROM economic_accounts a
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_assets e ON e.id = a.asset_id
   WHERE NOT EXISTS (
     SELECT 1 FROM economic_account_policies p
      WHERE p.owner_type = o.owner_type
        AND p.account_type = a.account_type
        AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY')
   )
  UNION ALL
  SELECT 'invalid_resource_inventory_owners', COUNT(*)::BIGINT
    FROM economic_accounts a
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_assets e ON e.id = a.asset_id
   WHERE a.account_type = 'INVENTORY' AND e.asset_kind = 'RESOURCE'
     AND o.owner_type NOT IN ('HOUSE', 'CORPORATION')
  UNION ALL
  SELECT 'invalid_market_order_owners', COUNT(*)::BIGINT
    FROM market_orders m
    JOIN owner_registry o ON o.economic_id = m.owner_economic_id
   WHERE o.owner_type NOT IN ('HOUSE', 'CORPORATION')
  UNION ALL
  SELECT 'invalid_market_orders', COUNT(*)::BIGINT
    FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units
  UNION ALL
  SELECT 'invalid_asset_transfer_balance', COUNT(*)::BIGINT
    FROM (
      SELECT t.id, e.asset_id
        FROM economic_transactions t
        JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
        JOIN economic_entries e ON e.transaction_id = t.id
       WHERE k.semantic_class = 'ASSET_TRANSFER'
       GROUP BY t.id, e.asset_id
      HAVING SUM(e.delta_units) <> 0
    ) invalid
  UNION ALL
  SELECT 'invalid_resource_production_authority', COUNT(*)::BIGINT
    FROM economic_transactions t
    JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
   WHERE k.semantic_class = 'RESOURCE_PRODUCTION'
     AND (t.source_type <> 'SYSTEM_PRODUCTION' OR NOT EXISTS (
       SELECT 1 FROM economic_entries e
       JOIN economic_accounts a ON a.id = e.account_id
       JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE e.transaction_id = t.id AND a.account_type = 'SYSTEM_ACCOUNT'
         AND o.owner_type = 'SYSTEM' AND e.delta_units < 0
     ))
  UNION ALL
  SELECT 'invalid_resource_consumption_authority', COUNT(*)::BIGINT
    FROM economic_transactions t
    JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
   WHERE k.semantic_class = 'RESOURCE_CONSUMPTION'
     AND (t.source_type <> 'SYSTEM_CONSUMPTION' OR NOT EXISTS (
       SELECT 1 FROM economic_entries e
       JOIN economic_accounts a ON a.id = e.account_id
       JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE e.transaction_id = t.id AND a.account_type = 'SYSTEM_ACCOUNT'
         AND o.owner_type = 'SYSTEM' AND e.delta_units > 0
     ))
  UNION ALL
  SELECT 'invalid_credit_issuance_authority', COUNT(*)::BIGINT
    FROM economic_transactions t
    JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
   WHERE k.semantic_class = 'CREDIT_ISSUANCE'
     AND t.source_type <> 'SYSTEM_ISSUANCE'
  UNION ALL
  SELECT 'invalid_house_current_human', COUNT(*)::BIGINT
    FROM houses h JOIN humans x ON x.id = h.current_human_id
   WHERE x.status <> 'ACTIVE'
  UNION ALL
  SELECT 'invalid_budget_authority', COUNT(*)::BIGINT
    FROM institution_budget_lines
   WHERE authorized_units < committed_units + spent_units;
$$;

-- 4. Backfill existing Corporations
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT economic_id FROM owner_registry WHERE owner_type = 'CORPORATION' LOOP
    PERFORM earth_provision_corporation_economy(r.economic_id);
  END LOOP;
END;
$$;

-- 5. Ensure active V5 founding policy version exists
INSERT INTO v5_corporation_founding_policy_versions
  (id, version, founding_fee_units, initial_treasury_reserve_units, initial_house_base_capacity_rate_units, effective_from_game_day, status, rules_version)
VALUES
  ('V5-FOUNDING-POLICY-1', 1, 1000000, 1000000, 10000, 1, 'ACTIVE', 'v5-founding-v1')
ON CONFLICT (id) DO NOTHING;

