-- Technology & Research V2 Plan 21: corporation-to-corporation IP licenses.

CREATE TABLE IF NOT EXISTS technology_license_contracts (
  id TEXT PRIMARY KEY,
  patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  licensor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  licensee_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  upfront_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (upfront_fee_units >= 0),
  daily_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (daily_fee_units >= 0),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'EXPIRED', 'TERMINATED')),
  paid_through_game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (licensee_economic_id <> licensor_economic_id),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  CHECK (paid_through_game_day < effective_from_game_day)
);

CREATE INDEX IF NOT EXISTS technology_license_contracts_licensee_idx
  ON technology_license_contracts (licensee_economic_id, status, effective_from_game_day, effective_to_game_day);
CREATE INDEX IF NOT EXISTS technology_license_contracts_patent_idx
  ON technology_license_contracts (patent_id, status);

CREATE OR REPLACE FUNCTION earth_create_technology_license_contract(
  p_patent_id TEXT,
  p_licensor_economic_id BIGINT,
  p_licensee_economic_id BIGINT,
  p_effective_from_game_day BIGINT,
  p_effective_to_game_day BIGINT,
  p_upfront_fee_units BIGINT,
  p_daily_fee_units BIGINT,
  p_rules_version TEXT,
  p_correlation_id TEXT
)
RETURNS TABLE (contract_id TEXT, transaction_id BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE v_contract_id TEXT;
DECLARE v_transaction_id BIGINT;
DECLARE v_debit_account BIGINT;
DECLARE v_credit_account BIGINT;
DECLARE v_patent_owner BIGINT;
DECLARE v_technology_id TEXT;
DECLARE v_game_day BIGINT;
BEGIN
  SELECT c.id INTO v_contract_id
  FROM technology_license_contracts c
  WHERE c.correlation_id = p_correlation_id;
  IF v_contract_id IS NOT NULL THEN
    contract_id := v_contract_id;
    transaction_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_effective_from_game_day < 0 OR p_upfront_fee_units < 0 OR p_daily_fee_units < 0
     OR p_effective_to_game_day IS NOT NULL AND p_effective_to_game_day < p_effective_from_game_day
     OR p_licensor_economic_id = p_licensee_economic_id THEN
    RAISE EXCEPTION 'Invalid corporation IP license terms';
  END IF;

  SELECT p.owner_economic_id, p.technology_id
  INTO v_patent_owner, v_technology_id
  FROM technology_patents p
  WHERE p.id = p_patent_id AND p.status = 'ACTIVE'
  FOR UPDATE;
  IF v_patent_owner IS NULL THEN
    RAISE EXCEPTION 'Active patent is required for a license';
  END IF;
  IF v_patent_owner <> p_licensor_economic_id THEN
    RAISE EXCEPTION 'Licensor does not own the patent';
  END IF;
  IF NOT earth_technology_is_patentable(v_technology_id) THEN
    RAISE EXCEPTION 'Technology is not patentable';
  END IF;
  IF EXISTS (SELECT 1 FROM technology_public_domain d WHERE d.technology_id = v_technology_id) THEN
    RAISE EXCEPTION 'Public-domain technology does not require a license';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM owner_registry WHERE economic_id = p_licensee_economic_id AND owner_type ILIKE 'corporation') THEN
    RAISE EXCEPTION 'Only corporations may be IP licensees';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM owner_registry WHERE economic_id = p_licensor_economic_id AND owner_type ILIKE 'corporation') THEN
    RAISE EXCEPTION 'Only corporations may be IP licensors';
  END IF;

  SELECT game_day INTO v_game_day FROM world_state WHERE id = 'WORLD';
  SELECT a.id INTO v_debit_account
  FROM economic_accounts a
  WHERE a.owner_economic_id = p_licensee_economic_id AND a.asset_id = 1
    AND a.status = 'active' AND a.is_default_settlement
  ORDER BY a.id LIMIT 1;
  SELECT a.id INTO v_credit_account
  FROM economic_accounts a
  WHERE a.owner_economic_id = p_licensor_economic_id AND a.asset_id = 1
    AND a.status = 'active' AND a.is_default_settlement
  ORDER BY a.id LIMIT 1;
  IF p_upfront_fee_units > 0 AND (v_debit_account IS NULL OR v_credit_account IS NULL) THEN
    RAISE EXCEPTION 'Default CREDIT settlement accounts are required for license fees';
  END IF;

  IF p_upfront_fee_units > 0 THEN
    SELECT e.transaction_id INTO v_transaction_id
    FROM earth_post_transaction(
      p_correlation_id, COALESCE(v_game_day, p_effective_from_game_day), 1439,
      'IP_LICENSE_UPFRONT', 'TECHNOLOGY_LICENSE', p_patent_id, p_rules_version,
      jsonb_build_array(
        jsonb_build_object('account_id', v_debit_account, 'delta', -p_upfront_fee_units, 'reason_code', 'IP_LICENSE_UPFRONT'),
        jsonb_build_object('account_id', v_credit_account, 'delta', p_upfront_fee_units, 'reason_code', 'IP_LICENSE_UPFRONT')
      )
    ) e;
  END IF;

  v_contract_id := 'LICENSE-' || md5(p_correlation_id);
  INSERT INTO technology_license_contracts (
    id, patent_id, licensor_economic_id, licensee_economic_id,
    effective_from_game_day, effective_to_game_day, upfront_fee_units,
    daily_fee_units, status, paid_through_game_day, rules_version, correlation_id
  ) VALUES (
    v_contract_id, p_patent_id, p_licensor_economic_id, p_licensee_economic_id,
    p_effective_from_game_day, p_effective_to_game_day, p_upfront_fee_units,
    p_daily_fee_units, 'ACTIVE', p_effective_from_game_day - 1, p_rules_version, p_correlation_id
  );
  PERFORM earth_grant_corporation_technology_access(
    p_licensee_economic_id, v_technology_id, 'LICENSED', v_contract_id,
    p_effective_from_game_day, p_effective_to_game_day
  );

  contract_id := v_contract_id;
  transaction_id := v_transaction_id;
  RETURN NEXT;
END;
$$;

COMMENT ON TABLE technology_license_contracts IS
  'Corporation-to-corporation patent licenses with immutable game-day terms and Economy V2 fee settlement.';
