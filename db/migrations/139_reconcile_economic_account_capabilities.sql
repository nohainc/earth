-- EARTH ACTIVE MIGRATION: reconcile legacy economic accounts with canonical account policies

-- 1. Ensure canonical SYSTEM_ACCOUNT records exist for all SYSTEM owners and assets
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type)
SELECT o.economic_id, a.id, 'SYSTEM_ACCOUNT'
  FROM owner_registry o
 CROSS JOIN economic_assets a
 WHERE o.owner_type = 'SYSTEM'
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

-- 2. Re-point any entries referencing non-SYSTEM_ACCOUNT accounts on SYSTEM owners to SYSTEM_ACCOUNT
UPDATE economic_entries e
   SET account_id = canonical.id
  FROM economic_accounts legacy
  JOIN owner_registry o ON o.economic_id = legacy.owner_economic_id
  JOIN economic_accounts canonical
    ON canonical.owner_economic_id = legacy.owner_economic_id
   AND canonical.asset_id = legacy.asset_id
   AND canonical.account_type = 'SYSTEM_ACCOUNT'
 WHERE e.account_id = legacy.id
   AND o.owner_type = 'SYSTEM'
   AND legacy.account_type <> 'SYSTEM_ACCOUNT';

-- 3. Delete obsolete/invalid accounts on SYSTEM owners
DELETE FROM economic_accounts a
 USING owner_registry o
 WHERE o.economic_id = a.owner_economic_id
   AND o.owner_type = 'SYSTEM'
   AND a.account_type <> 'SYSTEM_ACCOUNT'
   AND NOT EXISTS (SELECT 1 FROM economic_entries e WHERE e.account_id = a.id)
   AND NOT EXISTS (SELECT 1 FROM market_order_reservations r WHERE r.escrow_account_id = a.id);

-- 4. Delete unreferenced, zero-balance invalid capability accounts across all owner types
-- (e.g. historical INVENTORY/WALLET accounts on EARTH, BANK, etc. that violate economic_account_policies)
DELETE FROM economic_accounts a
 WHERE NOT EXISTS (
   SELECT 1
     FROM owner_registry o
     JOIN economic_assets e ON e.id = a.asset_id
     JOIN economic_account_policies p ON p.owner_type = o.owner_type
    WHERE o.economic_id = a.owner_economic_id
      AND p.account_type = a.account_type
      AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY')
 )
 AND a.balance_units = 0
 AND NOT EXISTS (SELECT 1 FROM economic_entries e WHERE e.account_id = a.id)
 AND NOT EXISTS (SELECT 1 FROM market_order_reservations r WHERE r.escrow_account_id = a.id)
 AND NOT EXISTS (SELECT 1 FROM global_program_fundings g WHERE g.recipient_account_id = a.id);
