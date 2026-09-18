-- EARTH ACTIVE MIGRATION: 129_v5_final_legacy_cutover
-- Final cutover guards preventing legacy/retired records and enforcing canonical V5 operation.

-- 1. Ensure all legacy building catalog items are permanently marked inactive
UPDATE building_catalog
   SET active = FALSE
 WHERE code IN (
   'housing_t1',
   'energy_plant_t1',
   'food_farm_t1',
   'material_fab_t1',
   'compute_fab_t1',
   'component_fab_t1',
   'urban-district-module'
 ) OR id IN (
   'housing_t1',
   'energy_plant_t1',
   'food_farm_t1',
   'material_fab_t1',
   'compute_fab_t1',
   'component_fab_t1',
   'urban-district-module'
 );

-- 2. Database trigger guard preventing construction / activation of retired building types
CREATE OR REPLACE FUNCTION earth_guard_v5_building_creation()
RETURNS TRIGGER AS $$
DECLARE
  v_catalog_active BOOLEAN;
BEGIN
  IF NEW.status = 'ACTIVE' THEN
    SELECT active INTO v_catalog_active
      FROM building_catalog
     WHERE id = NEW.catalog_id;

    IF v_catalog_active IS NOT TRUE THEN
      RAISE EXCEPTION 'Legacy or retired building catalog item (%) cannot be instantiated in V5', NEW.catalog_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_v5_building_creation ON buildings;
CREATE TRIGGER trg_guard_v5_building_creation
  BEFORE INSERT OR UPDATE OF catalog_id, status ON buildings
  FOR EACH ROW
  EXECUTE FUNCTION earth_guard_v5_building_creation();

-- 3. Database trigger guard preventing allocations for retired services
CREATE OR REPLACE FUNCTION earth_guard_v5_retired_service_allocation()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.service_code IN ('HOUSING', 'ENERGY') THEN
    RAISE EXCEPTION 'Service type (%) is retired in V5 economic core', NEW.service_code;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_v5_retired_service_allocation ON service_allocations;
CREATE TRIGGER trg_guard_v5_retired_service_allocation
  BEFORE INSERT ON service_allocations
  FOR EACH ROW
  EXECUTE FUNCTION earth_guard_v5_retired_service_allocation();

-- 4. Database trigger guard preventing active need rules for retired needs
CREATE OR REPLACE FUNCTION earth_guard_v5_retired_need_rules()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'ACTIVE' AND NEW.need_code IN ('HOUSING', 'ENERGY') THEN
    RAISE EXCEPTION 'Need rule (%) is retired in V5 economic core', NEW.need_code;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_v5_retired_need_rules ON need_rules;
CREATE TRIGGER trg_guard_v5_retired_need_rules
  BEFORE INSERT OR UPDATE OF status, need_code ON need_rules
  FOR EACH ROW
  EXECUTE FUNCTION earth_guard_v5_retired_need_rules();

-- 5. Update earth_integrity_report() with legacy cutover checks
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
   WHERE authorized_units < committed_units + spent_units
  UNION ALL
  SELECT 'invalid_retired_building_catalog_records', COUNT(*)::BIGINT
    FROM buildings b
    JOIN building_catalog c ON c.id = b.catalog_id
   WHERE b.status = 'ACTIVE' AND c.active = FALSE
  UNION ALL
  SELECT 'invalid_active_retired_need_rules', COUNT(*)::BIGINT
    FROM need_rules
   WHERE status = 'ACTIVE' AND need_code IN ('HOUSING', 'ENERGY');
$$;
