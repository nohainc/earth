-- Cities & Corporations V2 Plan 1.
-- Economy V2 is the sole authoritative source for institutional CREDIT.

DO $$
DECLARE
  mismatch RECORD;
BEGIN
  SELECT institution_id, scalar_treasury, economic_treasury
  INTO mismatch
  FROM (
    SELECT c.id AS institution_id,
           c.treasury AS scalar_treasury,
           COALESCE(SUM(a.balance), 0)::NUMERIC / 100.0 AS economic_treasury
    FROM cities c
    JOIN owner_registry o ON o.id = c.id
    LEFT JOIN economic_accounts a
      ON a.owner_economic_id = o.economic_id
     AND a.asset_id = 1
     AND a.account_type = 3
     AND a.is_default_settlement
     AND a.status = 'active'
    GROUP BY c.id, c.treasury
    UNION ALL
    SELECT c.id,
           c.treasury,
           COALESCE(SUM(a.balance), 0)::NUMERIC / 100.0
    FROM corporations c
    JOIN owner_registry o ON o.id = c.id
    LEFT JOIN economic_accounts a
      ON a.owner_economic_id = o.economic_id
     AND a.asset_id = 1
     AND a.account_type = 3
     AND a.is_default_settlement
     AND a.status = 'active'
    GROUP BY c.id, c.treasury
  ) values_to_check
  WHERE scalar_treasury <> economic_treasury
  ORDER BY institution_id
  LIMIT 1;

  IF mismatch.institution_id IS NOT NULL THEN
    RAISE EXCEPTION
      'Institution treasury mismatch for %: scalar %, Economy V2 %',
      mismatch.institution_id, mismatch.scalar_treasury, mismatch.economic_treasury;
  END IF;
END;
$$;

-- Ensure the semantic institutional account topology exists before the
-- scalar columns disappear. Treasury is the sole default settlement account.
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, status)
SELECT o.economic_id, 1, 3, TRUE, 'active'
FROM owner_registry o
WHERE o.owner_type IN ('city', 'corporation')
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts a
    WHERE a.owner_economic_id = o.economic_id
      AND a.asset_id = 1
      AND a.account_type = 3
      AND a.status = 'active'
  );

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, status)
SELECT o.economic_id, 1, t.account_type, FALSE, 'active'
FROM owner_registry o
CROSS JOIN (VALUES (4), (5)) AS t(account_type)
WHERE o.owner_type IN ('city', 'corporation')
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts a
    WHERE a.owner_economic_id = o.economic_id
      AND a.asset_id = 1
      AND a.account_type = t.account_type
      AND a.status = 'active'
  );

ALTER TABLE cities DROP COLUMN IF EXISTS treasury;
ALTER TABLE corporations DROP COLUMN IF EXISTS treasury;

COMMENT ON TABLE economic_accounts IS
  'Authoritative balances for all economic owners, including City and Corporation treasury, operations, and reserve accounts.';
