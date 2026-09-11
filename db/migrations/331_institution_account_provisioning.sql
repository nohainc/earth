-- Cities, Corporations & Budgets V2 Plan 21.
-- Newly formed institutions receive their final Economy V2 cash topology.

CREATE OR REPLACE FUNCTION earth_provision_institution_accounts(p_institution_id TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE v_owner_economic_id BIGINT; v_owner_type TEXT; v_count INTEGER;
BEGIN
  SELECT economic_id, owner_type INTO v_owner_economic_id, v_owner_type
    FROM owner_registry
   WHERE id = p_institution_id AND status = 'active';
  IF v_owner_economic_id IS NULL OR v_owner_type NOT IN ('city', 'corporation') THEN
    RAISE EXCEPTION 'Institution % has no active city/corporation economic owner', p_institution_id;
  END IF;

  INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, status, legacy_account_id)
  SELECT v_owner_economic_id, 1, t.account_type, t.account_type = 3, 'active',
         format('institution:%s:%s', p_institution_id, t.account_type)
    FROM (VALUES (3), (4), (5)) AS t(account_type)
   WHERE NOT EXISTS (
     SELECT 1 FROM economic_accounts a
      WHERE a.owner_economic_id = v_owner_economic_id
        AND a.asset_id = 1 AND a.account_type = t.account_type AND a.status = 'active'
   );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION earth_provision_institution_accounts(TEXT) IS
  'Idempotently provisions CREDIT TREASURY, OPERATIONS, and RESERVE accounts for a new institution.';
