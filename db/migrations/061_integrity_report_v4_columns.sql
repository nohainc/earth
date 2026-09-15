-- EARTH ACTIVE MIGRATION: keep integrity reporting aligned with the V4 schema.
-- Migration 006 moved building resource behavior into catalog effects; the
-- older integrity function still referenced the removed JSON columns.

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'negative_economic_balances', COUNT(*)::BIGINT
    FROM economic_accounts WHERE balance_units < 0
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
     AND o.owner_type <> 'HOUSE'
  UNION ALL
  SELECT 'invalid_market_order_owners', COUNT(*)::BIGINT
    FROM market_orders m
    JOIN owner_registry o ON o.economic_id = m.owner_economic_id
   WHERE o.owner_type <> 'HOUSE'
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
       SELECT 1
         FROM economic_entries e
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
       SELECT 1
         FROM economic_entries e
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
