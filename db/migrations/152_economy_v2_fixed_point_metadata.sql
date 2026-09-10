-- Economy V2 Plan 3: make fixed-point precision explicit and verify the
-- additive legacy-to-V2 conversion before any future accounting cutover.

ALTER TABLE economic_assets
  ADD COLUMN IF NOT EXISTS scale BIGINT,
  ADD COLUMN IF NOT EXISTS decimals SMALLINT;

UPDATE economic_assets
SET scale = unit_scale,
    decimals = CASE WHEN unit_scale = 100 THEN 2 ELSE 6 END
WHERE scale IS NULL OR decimals IS NULL;

ALTER TABLE economic_assets
  ALTER COLUMN scale SET NOT NULL,
  ALTER COLUMN decimals SET NOT NULL;

ALTER TABLE economic_assets
  ADD CONSTRAINT economic_assets_scale_decimals_ck
  CHECK ((scale = 100 AND decimals = 2) OR (scale = 1000000 AND decimals = 6));

CREATE INDEX IF NOT EXISTS economic_assets_scale_idx
  ON economic_assets (scale, decimals);

-- Numeric legacy values must be exactly representable at the V2 scale.
DO $$
DECLARE
  invalid_count BIGINT;
BEGIN
  SELECT COUNT(*) INTO invalid_count
  FROM account_balances
  WHERE currency = 'CREDIT'
    AND balance * 100 <> ROUND(balance * 100);
  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Cannot convert % CREDIT balances exactly to cents', invalid_count;
  END IF;

  SELECT COUNT(*) INTO invalid_count
  FROM resource_balances
  WHERE amount * 1000000 <> ROUND(amount * 1000000);
  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Cannot convert % resource balances exactly to micro-units', invalid_count;
  END IF;
END;
$$;

-- Verify every legacy owner/asset aggregate represented by the additive V2
-- default account. This deliberately compares sums, not row counts, because
-- the old credit model permits multiple accounts per owner.
DO $$
DECLARE
  mismatch_count BIGINT;
BEGIN
  WITH expected AS (
    SELECT o.economic_id AS owner_economic_id, 1::SMALLINT AS asset_id,
           ROUND(COALESCE(SUM(ab.balance), 0) * 100)::BIGINT AS balance
    FROM owner_registry o
    LEFT JOIN account_balances ab ON ab.owner_id = o.id AND ab.currency = 'CREDIT'
    GROUP BY o.economic_id
    UNION ALL
    SELECT o.economic_id, a.id,
           ROUND(COALESCE(SUM(rb.amount), 0) * 1000000)::BIGINT
    FROM owner_registry o
    CROSS JOIN economic_assets a
    LEFT JOIN resource_balances rb
      ON rb.owner_id = o.id AND UPPER(rb.resource) = a.code
    WHERE a.id <> 1
    GROUP BY o.economic_id, a.id
  )
  SELECT COUNT(*) INTO mismatch_count
  FROM expected e
  JOIN economic_accounts v
    ON v.owner_economic_id = e.owner_economic_id
   AND v.asset_id = e.asset_id
   AND v.is_default_settlement
  WHERE v.balance <> e.balance;

  IF mismatch_count > 0 THEN
    RAISE EXCEPTION 'V2 fixed-point conversion mismatch in % default accounts', mismatch_count;
  END IF;
END;
$$;

COMMENT ON COLUMN economic_assets.scale IS
  'Fixed-point multiplier used to store one display unit as an integer.';
COMMENT ON COLUMN economic_assets.decimals IS
  'Display precision corresponding to scale.';
