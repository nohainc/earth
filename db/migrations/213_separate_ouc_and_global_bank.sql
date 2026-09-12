-- Finance V2 Plan 3: separate fiscal OUC balances from bank liquidity.

INSERT INTO owner_registry (id, owner_type, source_id)
VALUES ('SYSTEM-GLOBAL-BANK', 'system', 'SYSTEM-GLOBAL-BANK')
ON CONFLICT (id) DO NOTHING;

-- OUC is a fiscal institution. Its default CREDIT settlement account is the
-- TREASURY; OPERATIONS and RESERVE are separate pools, not aliases.
UPDATE economic_accounts a
SET is_default_settlement = FALSE, updated_at = CURRENT_TIMESTAMP
FROM owner_registry o
WHERE a.owner_economic_id = o.economic_id AND o.id = 'OUC' AND a.asset_id = 1;

-- The legacy OUC account may already have been copied into Economy V2 by an
-- earlier migration. The legacy identifier is globally unique, so detach it
-- from any non-OUC account and reuse that account for the canonical OUC
-- treasury instead of attempting a conflicting insert.
UPDATE economic_accounts existing
SET legacy_account_id = NULL,
    updated_at = CURRENT_TIMESTAMP
FROM owner_registry ouc
WHERE existing.legacy_account_id = 'account-ouc-treasury'
  AND ouc.id = 'OUC'
  AND existing.owner_economic_id <> ouc.economic_id;

UPDATE economic_accounts existing
SET owner_economic_id = ouc.economic_id,
    asset_id = 1,
    account_type = 3,
    is_default_settlement = TRUE,
    status = 'active',
    updated_at = CURRENT_TIMESTAMP
FROM owner_registry ouc
WHERE existing.legacy_account_id = 'account-ouc-treasury'
  AND ouc.id = 'OUC'
  AND NOT EXISTS (
    SELECT 1
    FROM economic_accounts treasury
    WHERE treasury.owner_economic_id = ouc.economic_id
      AND treasury.asset_id = 1
      AND treasury.account_type = 3
  );

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, 3, COALESCE((SELECT balance FROM economic_accounts x JOIN economic_account_migrations m ON m.economic_account_id = x.id WHERE m.legacy_account_id = 'account-ouc-treasury' LIMIT 1), 0), TRUE, 'account-ouc-treasury'
FROM owner_registry o
WHERE o.id = 'OUC'
  AND NOT EXISTS (SELECT 1 FROM economic_accounts x WHERE x.owner_economic_id = o.economic_id AND x.asset_id = 1 AND x.account_type = 3);
UPDATE economic_accounts a SET is_default_settlement = TRUE, legacy_account_id = COALESCE(a.legacy_account_id, 'account-ouc-treasury'), updated_at = CURRENT_TIMESTAMP
FROM owner_registry o WHERE a.owner_economic_id = o.economic_id AND o.id = 'OUC' AND a.asset_id = 1 AND a.account_type = 3;

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.account_type, FALSE,
       'account-ouc-' || CASE t.account_type WHEN 4 THEN 'operations' ELSE 'reserve' END
FROM owner_registry o CROSS JOIN (VALUES (4), (5)) t(account_type)
WHERE o.id = 'OUC'
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = t.account_type);

-- The bank owns its reserve and operations accounts. The old legacy identity
-- is remapped to the new reserve so existing domain journals remain traceable.
-- Reuse the already-migrated legacy account when present. Earlier Economy V2
-- migrations registered it under GLOBAL-CORPORATE-BANK; moving that account's
-- owner preserves its balance and history while avoiding a duplicate legacy
-- account identifier.
UPDATE economic_accounts legacy_bank
SET owner_economic_id = bank_owner.economic_id,
    updated_at = CURRENT_TIMESTAMP
FROM owner_registry bank_owner
WHERE legacy_bank.legacy_account_id = 'account-global-corporate-bank'
  AND bank_owner.id = 'SYSTEM-GLOBAL-BANK'
  AND NOT EXISTS (
    SELECT 1
    FROM economic_accounts existing
    WHERE existing.owner_economic_id = bank_owner.economic_id
      AND existing.asset_id = 1
      AND existing.account_type = 10
  );

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.account_type, FALSE,
       CASE t.account_type WHEN 10 THEN 'account-global-corporate-bank' ELSE 'account-global-bank-operations' END
FROM owner_registry o CROSS JOIN (VALUES (10), (4)) t(account_type)
WHERE o.id = 'SYSTEM-GLOBAL-BANK'
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = t.account_type);

UPDATE economic_accounts bank
SET balance = COALESCE((SELECT legacy_balance_units FROM economic_account_migrations m WHERE m.legacy_account_id = 'account-global-corporate-bank' LIMIT 1), bank.balance),
    updated_at = CURRENT_TIMESTAMP
FROM owner_registry o
WHERE bank.owner_economic_id = o.economic_id AND o.id = 'SYSTEM-GLOBAL-BANK' AND bank.asset_id = 1 AND bank.account_type = 10;

DELETE FROM economic_account_migrations WHERE legacy_account_id = 'account-global-corporate-bank';
INSERT INTO economic_account_migrations (legacy_account_id, economic_account_id, mapping_kind, legacy_balance_units, account_semantics)
SELECT 'account-global-corporate-bank', a.id, 'credit_account', a.balance, 'BANK_RESERVE'
FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10
ON CONFLICT (legacy_account_id) DO UPDATE SET economic_account_id = EXCLUDED.economic_account_id, legacy_balance_units = EXCLUDED.legacy_balance_units, account_semantics = EXCLUDED.account_semantics;

COMMENT ON TABLE economic_accounts IS 'Authoritative economic balances. OUC fiscal accounts and Global Bank accounts are distinct owners and must not be substituted.';
