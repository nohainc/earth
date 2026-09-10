-- Economy V2 Plan 18: explicit account semantics and bounded system sources.

CREATE TABLE IF NOT EXISTS economic_account_types (
  id SMALLINT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  allows_negative BOOLEAN NOT NULL DEFAULT FALSE,
  is_system_type BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT NOT NULL
);

INSERT INTO economic_account_types (id, code, allows_negative, is_system_type, description) VALUES
  (1, 'WALLET', FALSE, FALSE, 'Personal CREDIT account'),
  (2, 'INVENTORY', FALSE, FALSE, 'Physical asset inventory'),
  (3, 'TREASURY', FALSE, FALSE, 'Institutional CREDIT treasury'),
  (4, 'OPERATIONS', FALSE, FALSE, 'Operating account for institutional costs'),
  (5, 'RESERVE', FALSE, FALSE, 'Held reserve account'),
  (6, 'ESCROW', FALSE, FALSE, 'Temporarily restricted account'),
  (7, 'ISSUANCE', TRUE, TRUE, 'World source for explicitly created assets; negative balance represents issued supply'),
  (8, 'CONSUMPTION_SINK', FALSE, TRUE, 'World sink receiving explicitly consumed assets'),
  (9, 'MARKET_CLEARING', FALSE, TRUE, 'Temporary clearing account for market flows'),
  (10, 'BANK_RESERVE', FALSE, TRUE, 'Bank reserve backing banking operations')
ON CONFLICT (id) DO UPDATE SET
  code = EXCLUDED.code, allows_negative = EXCLUDED.allows_negative,
  is_system_type = EXCLUDED.is_system_type, description = EXCLUDED.description;

ALTER TABLE economic_accounts
  DROP CONSTRAINT IF EXISTS economic_accounts_account_type_check,
  DROP CONSTRAINT IF EXISTS economic_accounts_balance_check;
ALTER TABLE economic_accounts
  ADD CONSTRAINT economic_accounts_account_type_fk
  FOREIGN KEY (account_type) REFERENCES economic_account_types(id);
ALTER TABLE economic_accounts
  ADD CONSTRAINT economic_accounts_nonnegative_unless_issuance_ck
  CHECK (balance >= 0 OR account_type = 7);

CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_system_type_uq
  ON economic_accounts (owner_economic_id, asset_id, account_type)
  WHERE account_type IN (7, 8, 9, 10) AND status = 'active';

-- One source and one sink for each asset, plus one market-clearing account;
-- BANK_RESERVE is meaningful only for CREDIT.
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement)
SELECT o.economic_id, a.id, t.id, FALSE
FROM owner_registry o
CROSS JOIN economic_assets a
JOIN economic_account_types t ON t.id IN (7, 8, 9)
WHERE o.id = 'SYSTEM'
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts existing
    WHERE existing.owner_economic_id = o.economic_id
      AND existing.asset_id = a.id AND existing.account_type = t.id
  )
UNION ALL
SELECT o.economic_id, 1, 10, FALSE
FROM owner_registry o
WHERE o.id = 'SYSTEM'
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts existing
    WHERE existing.owner_economic_id = o.economic_id
      AND existing.asset_id = 1 AND existing.account_type = 10
  );

-- Update both posting primitives so only cataloged negative-capacity accounts
-- may cross below zero.
DO $$
DECLARE
  function_name TEXT;
  definition_text TEXT;
  old_fragment TEXT := 'a.status <> ''active'' OR a.balance + r.delta < 0';
  new_fragment TEXT := 'a.status <> ''active'' OR (a.balance + r.delta < 0 AND NOT EXISTS (SELECT 1 FROM economic_account_types t WHERE t.id = a.account_type AND t.allows_negative))';
BEGIN
  FOREACH function_name IN ARRAY ARRAY['earth_post_transaction', 'earth_post_settlement_batch'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO definition_text
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = function_name
    LIMIT 1;
    IF definition_text IS NULL OR position(old_fragment IN definition_text) = 0 THEN
      RAISE EXCEPTION 'Cannot update negative-balance guard in %', function_name;
    END IF;
    EXECUTE replace(definition_text, old_fragment, new_fragment);
  END LOOP;
END;
$$;
