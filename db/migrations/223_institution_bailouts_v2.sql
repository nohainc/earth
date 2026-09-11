-- Finance V2 Plan 13: explicit fiscal and monetary recovery instruments.

CREATE TABLE IF NOT EXISTS institution_bailouts (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  bailout_kind TEXT NOT NULL CHECK (bailout_kind IN ('FISCAL', 'MONETARY')),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  source_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  target_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  economic_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  governance_authorization TEXT,
  reason TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION earth_post_fiscal_bailout(
  p_institution_id TEXT,
  p_amount_units BIGINT,
  p_correlation_id TEXT,
  p_reason TEXT DEFAULT 'Institution fiscal bailout'
)
RETURNS institution_bailouts
LANGUAGE plpgsql
AS $$
DECLARE
  existing institution_bailouts;
  institution_owner BIGINT;
  ouc_owner BIGINT;
  source_account BIGINT;
  target_account BIGINT;
  world RECORD;
  posting RECORD;
  result institution_bailouts;
BEGIN
  SELECT * INTO existing FROM institution_bailouts WHERE correlation_id = p_correlation_id;
  IF FOUND THEN RETURN existing; END IF;
  IF p_amount_units IS NULL OR p_amount_units <= 0 THEN RAISE EXCEPTION 'Fiscal bailout amount must be positive'; END IF;
  SELECT economic_id INTO institution_owner FROM owner_registry WHERE id = p_institution_id AND owner_type IN ('city', 'corporation') AND status = 'active';
  SELECT economic_id INTO ouc_owner FROM owner_registry WHERE id = 'OUC' AND status = 'active';
  SELECT id INTO source_account FROM economic_accounts WHERE owner_economic_id = ouc_owner AND asset_id = 1 AND account_type = 3 AND is_default_settlement AND status = 'active';
  SELECT id INTO target_account FROM economic_accounts WHERE owner_economic_id = institution_owner AND asset_id = 1 AND account_type = 3 AND is_default_settlement AND status = 'active';
  SELECT game_day, game_minute INTO world FROM world_state WHERE id = 'WORLD';
  IF institution_owner IS NULL OR source_account IS NULL OR target_account IS NULL THEN RAISE EXCEPTION 'V2 bailout accounts are unavailable'; END IF;
  SELECT * INTO posting FROM earth_post_transaction(
    p_correlation_id, world.game_day, world.game_minute, 'fiscal_bailout', 'ouc', p_institution_id, 'finance-v2',
    jsonb_build_array(
      jsonb_build_object('account_id', source_account, 'delta', -p_amount_units, 'reason_code', 'FISCAL_BAILOUT'),
      jsonb_build_object('account_id', target_account, 'delta', p_amount_units, 'reason_code', 'FISCAL_BAILOUT')
    )
  );
  INSERT INTO institution_bailouts (institution_id, bailout_kind, amount_units, source_owner_economic_id, target_owner_economic_id, economic_transaction_id, reason, game_day, correlation_id)
  VALUES (p_institution_id, 'FISCAL', p_amount_units, ouc_owner, institution_owner, posting.transaction_id, p_reason, world.game_day, p_correlation_id)
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_monetary_emergency_support(
  p_institution_id TEXT,
  p_amount_units BIGINT,
  p_correlation_id TEXT,
  p_governance_authorization TEXT,
  p_reason TEXT
)
RETURNS institution_bailouts
LANGUAGE plpgsql
AS $$
DECLARE
  existing institution_bailouts;
  issuer_owner BIGINT;
  institution_owner BIGINT;
  issuer_account BIGINT;
  target_account BIGINT;
  world RECORD;
  posting RECORD;
  result institution_bailouts;
BEGIN
  IF NULLIF(BTRIM(p_governance_authorization), '') IS NULL OR NULLIF(BTRIM(p_reason), '') IS NULL THEN RAISE EXCEPTION 'Monetary support requires governance authorization and reason'; END IF;
  IF p_amount_units IS NULL OR p_amount_units <= 0 THEN RAISE EXCEPTION 'Monetary support amount must be positive'; END IF;
  SELECT * INTO existing FROM institution_bailouts WHERE correlation_id = p_correlation_id;
  IF FOUND THEN RETURN existing; END IF;
  SELECT economic_id INTO issuer_owner FROM owner_registry WHERE id = 'SYSTEM-MONETARY-AUTHORITY';
  SELECT economic_id INTO institution_owner FROM owner_registry WHERE id = p_institution_id AND owner_type IN ('city', 'corporation') AND status = 'active';
  SELECT id INTO issuer_account FROM economic_accounts WHERE owner_economic_id = issuer_owner AND asset_id = 1 AND account_type = 7 AND status = 'active';
  SELECT id INTO target_account FROM economic_accounts WHERE owner_economic_id = institution_owner AND asset_id = 1 AND account_type = 3 AND is_default_settlement AND status = 'active';
  SELECT game_day, game_minute INTO world FROM world_state WHERE id = 'WORLD';
  IF issuer_account IS NULL OR target_account IS NULL THEN RAISE EXCEPTION 'V2 monetary support accounts are unavailable'; END IF;
  SELECT * INTO posting FROM earth_post_monetary_operation(
    p_correlation_id, world.game_day, world.game_minute, 'MONETARY_STABILIZATION', p_institution_id, p_governance_authorization,
    jsonb_build_array(
      jsonb_build_object('account_id', issuer_account, 'delta', -p_amount_units, 'reason_code', 'MONETARY_STABILIZATION'),
      jsonb_build_object('account_id', target_account, 'delta', p_amount_units, 'reason_code', 'MONETARY_STABILIZATION')
    )
  );
  INSERT INTO institution_bailouts (institution_id, bailout_kind, amount_units, source_owner_economic_id, target_owner_economic_id, economic_transaction_id, governance_authorization, reason, game_day, correlation_id)
  VALUES (p_institution_id, 'MONETARY', p_amount_units, issuer_owner, institution_owner, posting.transaction_id, p_governance_authorization, p_reason, world.game_day, p_correlation_id)
  RETURNING * INTO result;
  RETURN result;
END;
$$;
