-- Economy V2 Plan 2: one account model for CREDIT and all five resources.
-- Legacy balance tables remain authoritative for existing callers until later
-- cutover migrations. Balances here are integer atomic units: CREDIT uses
-- cents (100 units per CREDIT) and resources use micro-units (1,000,000 units).

CREATE SEQUENCE IF NOT EXISTS economic_accounts_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE TABLE IF NOT EXISTS economic_assets (
  id SMALLINT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE CHECK (code IN ('CREDIT','MATERIAL','COMPONENTS','ENERGY','COMPUTE','FOOD')),
  unit_scale BIGINT NOT NULL CHECK (unit_scale IN (100, 1000000)),
  is_currency BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO economic_assets (id, code, unit_scale, is_currency) VALUES
  (1, 'CREDIT', 100, TRUE),
  (2, 'MATERIAL', 1000000, FALSE),
  (3, 'COMPONENTS', 1000000, FALSE),
  (4, 'ENERGY', 1000000, FALSE),
  (5, 'COMPUTE', 1000000, FALSE),
  (6, 'FOOD', 1000000, FALSE)
ON CONFLICT (id) DO UPDATE
SET code = EXCLUDED.code, unit_scale = EXCLUDED.unit_scale, is_currency = EXCLUDED.is_currency;

CREATE TABLE IF NOT EXISTS economic_accounts (
  id BIGINT PRIMARY KEY DEFAULT nextval('economic_accounts_id_seq'),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  account_type SMALLINT NOT NULL CHECK (account_type IN (1, 2, 3, 4, 5, 6)),
  balance BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0),
  is_default_settlement BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed','archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_default_settlement_uq
  ON economic_accounts (owner_economic_id, asset_id)
  WHERE is_default_settlement;
CREATE INDEX IF NOT EXISTS economic_accounts_owner_asset_idx
  ON economic_accounts (owner_economic_id, asset_id, status);
CREATE INDEX IF NOT EXISTS economic_accounts_asset_owner_idx
  ON economic_accounts (asset_id, owner_economic_id, status);

COMMENT ON COLUMN economic_accounts.account_type IS
  '1=WALLET, 2=INVENTORY, 3=TREASURY, 4=OPERATIONS, 5=RESERVE, 6=ESCROW';
COMMENT ON COLUMN economic_accounts.balance IS
  'Integer atomic units; use economic_assets.unit_scale for display conversion.';

-- Seed one default account for every existing owner and asset. This is an
-- additive bridge: it does not alter or delete legacy balances.
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance, is_default_settlement)
SELECT o.economic_id,
       a.id,
       CASE
         WHEN a.id = 1 AND o.owner_type IN ('city', 'corporation') THEN 3
         WHEN a.id = 1 AND o.owner_type = 'system' THEN 5
         WHEN a.id = 1 THEN 1
         ELSE 2
       END,
       CASE
         WHEN a.id = 1 THEN COALESCE((
           SELECT ROUND(SUM(ab.balance) * 100)::BIGINT
           FROM account_balances ab
           WHERE ab.owner_id = o.id AND ab.currency = 'CREDIT'
         ), 0)
         ELSE COALESCE((
           SELECT ROUND(SUM(rb.amount) * 1000000)::BIGINT
           FROM resource_balances rb
           WHERE rb.owner_id = o.id
             AND UPPER(rb.resource) = a.code
         ), 0)
       END,
       TRUE
FROM owner_registry o
CROSS JOIN economic_assets a
WHERE NOT EXISTS (
  SELECT 1 FROM economic_accounts existing
  WHERE existing.owner_economic_id = o.economic_id
    AND existing.asset_id = a.id
    AND existing.is_default_settlement
);

SELECT setval(
  'economic_accounts_id_seq',
  GREATEST(1, COALESCE((SELECT MAX(id) FROM economic_accounts), 1)),
  true
);
