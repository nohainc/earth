-- Economy V2 Plan 21: shard-local clearing accounts within economic_accounts.

ALTER TABLE economic_accounts
  ADD COLUMN IF NOT EXISTS settlement_shard SMALLINT,
  ADD CONSTRAINT economic_accounts_settlement_shard_ck
  CHECK (settlement_shard IS NULL OR (account_type = 9 AND settlement_shard BETWEEN 0 AND 63));

-- The legacy system-type uniqueness rule allowed only one MARKET_CLEARING
-- account per asset. Replace it with shard-aware uniqueness.
DROP INDEX IF EXISTS economic_accounts_system_type_uq;
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_system_type_uq
  ON economic_accounts (owner_economic_id, asset_id, account_type)
  WHERE account_type IN (7, 8, 10) AND status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_shard_clearing_uq
  ON economic_accounts (owner_economic_id, asset_id, account_type, settlement_shard)
  WHERE account_type = 9 AND status = 'active' AND settlement_shard IS NOT NULL;
CREATE INDEX IF NOT EXISTS economic_accounts_shard_lookup_idx
  ON economic_accounts (settlement_shard, asset_id, account_type, status)
  WHERE settlement_shard IS NOT NULL;

INSERT INTO economic_accounts (
  owner_economic_id, asset_id, account_type, settlement_shard,
  balance, is_default_settlement, status
)
SELECT o.economic_id, a.id, 9, shards.shard, 0, FALSE, 'active'
FROM owner_registry o
CROSS JOIN economic_assets a
CROSS JOIN generate_series(0, 63) AS shards(shard)
WHERE o.id = 'SYSTEM'
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts existing
    WHERE existing.owner_economic_id = o.economic_id
      AND existing.asset_id = a.id
      AND existing.account_type = 9
      AND existing.settlement_shard = shards.shard
  );

CREATE OR REPLACE FUNCTION earth_get_shard_clearing_account(
  p_asset_id SMALLINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_account_id BIGINT;
BEGIN
  IF p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Clearing shard must be between 0 and 63';
  END IF;
  SELECT id INTO v_account_id
  FROM economic_accounts
  WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = 'SYSTEM')
    AND asset_id = p_asset_id AND account_type = 9
    AND settlement_shard = p_shard AND status = 'active';
  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'Missing shard clearing account for asset % shard %', p_asset_id, p_shard;
  END IF;
  RETURN v_account_id;
END;
$$;
