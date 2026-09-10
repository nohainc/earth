-- Economy V2 Plan 19: preserve legacy account topology during cutover.

ALTER TABLE economic_accounts
  ADD COLUMN IF NOT EXISTS legacy_account_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_legacy_account_uq
  ON economic_accounts (legacy_account_id)
  WHERE legacy_account_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS economic_account_migrations (
  legacy_account_id TEXT PRIMARY KEY,
  economic_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  mapping_kind TEXT NOT NULL CHECK (mapping_kind IN ('credit_account', 'resource_balance')),
  legacy_balance_units BIGINT NOT NULL,
  account_semantics TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Reuse the semantic system accounts provisioned by Plan 18 for legacy
-- MARKET_CLEARING and bank-reserve identities.
UPDATE economic_accounts ea
SET legacy_account_id = ab.account_id
FROM account_balances ab
JOIN owner_registry o ON o.id = ab.owner_id
WHERE ab.currency = 'CREDIT'
  AND ab.account_id IN ('account-market-clearing', 'account-global-corporate-bank')
  AND ea.owner_economic_id = o.economic_id
  AND ea.asset_id = 1
  AND ea.account_type = CASE WHEN ab.account_id = 'account-market-clearing' THEN 9 ELSE 10 END
  AND ea.legacy_account_id IS NULL;

-- The aggregate V2 defaults created by migration 151 must be split before
-- additional legacy accounts are copied, otherwise balances would double.
WITH canonical AS (
  SELECT ab.owner_id, ab.account_id, ab.balance,
         CASE
           WHEN o.owner_type = 'human' AND h.account_id = ab.account_id THEN TRUE
           WHEN o.owner_type = 'city' AND ab.account_id = 'account-city-' || o.id THEN TRUE
           WHEN o.owner_type = 'corporation' AND ab.account_id = 'account-corporation-' || o.id THEN TRUE
           ELSE FALSE
         END AS is_canonical
  FROM account_balances ab
  JOIN owner_registry o ON o.id = ab.owner_id
  LEFT JOIN humans h ON h.id = o.id
  WHERE ab.currency = 'CREDIT'
)
UPDATE economic_accounts ea
SET balance = COALESCE((
  SELECT ROUND(c.balance * 100)::BIGINT
  FROM canonical c
  JOIN owner_registry o ON o.id = c.owner_id
  WHERE c.is_canonical
    AND o.economic_id = ea.owner_economic_id
    AND ea.asset_id = 1
    AND ea.is_default_settlement
    AND ea.account_type = CASE WHEN o.owner_type = 'human' THEN 1 WHEN o.owner_type IN ('city','corporation') THEN 3 ELSE 5 END
), 0),
    updated_at = CURRENT_TIMESTAMP
WHERE ea.asset_id = 1 AND ea.is_default_settlement;

-- Copy every non-canonical legacy CREDIT account as its own V2 account.
INSERT INTO economic_accounts (
  owner_economic_id, asset_id, account_type, balance,
  is_default_settlement, status, legacy_account_id
)
SELECT o.economic_id, 1,
       CASE
         WHEN ab.account_id = 'account-market-clearing' THEN 9
         WHEN ab.account_id LIKE 'account-city-operations-%' THEN 4
         WHEN ab.account_id = 'account-global-corporate-bank' THEN 10
         WHEN ab.account_id LIKE 'account-ouc-%' THEN 3
         WHEN ab.account_id LIKE 'account-city-%' OR ab.account_id LIKE 'account-corporation-%' THEN 3
         ELSE 6
       END,
       ROUND(ab.balance * 100)::BIGINT,
       FALSE, 'active', ab.account_id
FROM account_balances ab
JOIN owner_registry o ON o.id = ab.owner_id
LEFT JOIN humans h ON h.id = o.id
WHERE ab.currency = 'CREDIT'
  AND NOT (
    (o.owner_type = 'human' AND h.account_id = ab.account_id)
    OR (o.owner_type = 'city' AND ab.account_id = 'account-city-' || o.id)
    OR (o.owner_type = 'corporation' AND ab.account_id = 'account-corporation-' || o.id)
  )
  AND NOT EXISTS (SELECT 1 FROM economic_accounts x WHERE x.legacy_account_id = ab.account_id);

-- Map canonical legacy accounts to their semantic V2 defaults.
INSERT INTO economic_account_migrations (legacy_account_id, economic_account_id, mapping_kind, legacy_balance_units, account_semantics)
SELECT ab.account_id, ea.id, 'credit_account', ROUND(ab.balance * 100)::BIGINT,
       CASE WHEN o.owner_type = 'human' THEN 'WALLET'
            WHEN o.owner_type IN ('city','corporation') THEN 'TREASURY'
            ELSE 'RESERVE' END
FROM account_balances ab
JOIN owner_registry o ON o.id = ab.owner_id
LEFT JOIN humans h ON h.id = o.id
JOIN economic_accounts ea ON ea.owner_economic_id = o.economic_id AND ea.asset_id = 1 AND ea.is_default_settlement
 AND ea.account_type = CASE WHEN o.owner_type = 'human' THEN 1 WHEN o.owner_type IN ('city','corporation') THEN 3 ELSE 5 END
WHERE ab.currency = 'CREDIT'
  AND (
    (o.owner_type = 'human' AND h.account_id = ab.account_id)
    OR (o.owner_type = 'city' AND ab.account_id = 'account-city-' || o.id)
    OR (o.owner_type = 'corporation' AND ab.account_id = 'account-corporation-' || o.id)
  )
ON CONFLICT (legacy_account_id) DO NOTHING;

-- Map every copied non-canonical CREDIT account.
INSERT INTO economic_account_migrations (legacy_account_id, economic_account_id, mapping_kind, legacy_balance_units, account_semantics)
SELECT ea.legacy_account_id, ea.id, 'credit_account', ea.balance,
       t.code
FROM economic_accounts ea
JOIN economic_account_types t ON t.id = ea.account_type
WHERE ea.legacy_account_id IS NOT NULL
ON CONFLICT (legacy_account_id) DO NOTHING;

-- Resource balances retain their owner/resource meaning through the V2
-- inventory account mapping; resources remain aggregated by owner/asset.
INSERT INTO economic_account_migrations (legacy_account_id, economic_account_id, mapping_kind, legacy_balance_units, account_semantics)
SELECT 'resource:' || rb.owner_id || ':' || rb.resource,
       ea.id, 'resource_balance', ROUND(rb.amount * 1000000)::BIGINT, 'INVENTORY'
FROM resource_balances rb
JOIN owner_registry o ON o.id = rb.owner_id
JOIN economic_assets asset ON asset.code = UPPER(rb.resource)
JOIN economic_accounts ea ON ea.owner_economic_id = o.economic_id
                         AND ea.asset_id = asset.id
                         AND ea.account_type = 2
                         AND ea.is_default_settlement
ON CONFLICT (legacy_account_id) DO NOTHING;
