-- Finance V2 Plan 2: institutional CREDIT lives in Economy V2 accounts.

CREATE OR REPLACE FUNCTION earth_provision_institution_economic_accounts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  treasury_account_id BIGINT;
BEGIN
  IF NEW.owner_type NOT IN ('city', 'corporation') THEN RETURN NEW; END IF;

  INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
  VALUES
    (NEW.economic_id, 1, 3, TRUE, 'account-' || lower(NEW.owner_type) || '-' || NEW.id),
    (NEW.economic_id, 1, 4, FALSE, 'account-' || lower(NEW.owner_type) || '-' || NEW.id || '-operations'),
    (NEW.economic_id, 1, 5, FALSE, 'account-' || lower(NEW.owner_type) || '-' || NEW.id || '-reserve')
  ON CONFLICT DO NOTHING;

  SELECT id INTO treasury_account_id
  FROM economic_accounts
  WHERE owner_economic_id = NEW.economic_id AND asset_id = 1 AND account_type = 3 AND is_default_settlement;

  INSERT INTO economic_account_migrations (legacy_account_id, economic_account_id, mapping_kind, legacy_balance_units, account_semantics)
  VALUES ('account-' || lower(NEW.owner_type) || '-' || NEW.id, treasury_account_id, 'credit_account', 0, 'TREASURY')
  ON CONFLICT (legacy_account_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS owner_registry_institution_accounts ON owner_registry;
CREATE TRIGGER owner_registry_institution_accounts
AFTER INSERT ON owner_registry
FOR EACH ROW EXECUTE FUNCTION earth_provision_institution_economic_accounts();

-- Backfill the semantic topology and transfer the scalar opening value once.
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, 3, ROUND(CASE WHEN o.owner_type = 'city' THEN c.treasury ELSE co.treasury END * 100)::BIGINT,
       TRUE, 'account-' || lower(o.owner_type) || '-' || o.id
FROM owner_registry o
LEFT JOIN cities c ON c.id = o.id AND o.owner_type = 'city'
LEFT JOIN corporations co ON co.id = o.id AND o.owner_type = 'corporation'
WHERE o.owner_type IN ('city', 'corporation')
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement);

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.account_type, FALSE,
       'account-' || lower(o.owner_type) || '-' || o.id || CASE t.account_type WHEN 4 THEN '-operations' ELSE '-reserve' END
FROM owner_registry o CROSS JOIN (VALUES (4), (5)) t(account_type)
WHERE o.owner_type IN ('city', 'corporation')
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = t.account_type);

INSERT INTO economic_account_migrations (legacy_account_id, economic_account_id, mapping_kind, legacy_balance_units, account_semantics)
SELECT a.legacy_account_id, a.id, 'credit_account', a.balance, et.code
FROM economic_accounts a JOIN economic_account_types et ON et.id = a.account_type
WHERE a.legacy_account_id IS NOT NULL
  AND a.legacy_account_id LIKE 'account-%'
  AND NOT EXISTS (SELECT 1 FROM economic_account_migrations m WHERE m.legacy_account_id = a.legacy_account_id);

-- Keep the old scalar values as a temporary compatibility projection until all
-- read callers are migrated; no new code should read or mutate them.
COMMENT ON COLUMN cities.treasury IS 'Deprecated compatibility projection; authoritative value is the default V2 CREDIT TREASURY account.';
COMMENT ON COLUMN corporations.treasury IS 'Deprecated compatibility projection; authoritative value is the default V2 CREDIT TREASURY account.';
