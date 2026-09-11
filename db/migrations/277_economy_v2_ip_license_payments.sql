-- Technology & Research V2 Plan 24: all IP license fees use Economy V2.

ALTER TABLE technology_license_contracts
  ADD COLUMN IF NOT EXISTS upfront_transaction_id BIGINT,
  ADD COLUMN IF NOT EXISTS last_daily_transaction_id BIGINT;

CREATE OR REPLACE FUNCTION earth_record_technology_license_upfront_transaction()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.upfront_fee_units > 0 AND NEW.upfront_transaction_id IS NULL THEN
    SELECT id INTO NEW.upfront_transaction_id
    FROM economic_transactions
    WHERE correlation_id = NEW.correlation_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS technology_license_contract_upfront_transaction_trigger
  ON technology_license_contracts;
CREATE TRIGGER technology_license_contract_upfront_transaction_trigger
  BEFORE INSERT ON technology_license_contracts
  FOR EACH ROW EXECUTE FUNCTION earth_record_technology_license_upfront_transaction();

UPDATE technology_license_contracts c
SET upfront_transaction_id = e.id
FROM economic_transactions e
WHERE c.upfront_fee_units > 0
  AND c.upfront_transaction_id IS NULL
  AND e.correlation_id = c.correlation_id;

CREATE TABLE IF NOT EXISTS technology_license_payments (
  id BIGSERIAL PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES technology_license_contracts(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  transaction_id BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (contract_id, game_day)
);

CREATE INDEX IF NOT EXISTS technology_license_payments_contract_idx
  ON technology_license_payments (contract_id, game_day);

CREATE OR REPLACE FUNCTION earth_settle_technology_license_fees(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_contract RECORD;
  v_debit_account BIGINT;
  v_credit_account BIGINT;
  v_balance BIGINT;
  v_transaction_id BIGINT;
  v_paid BIGINT := 0;
  v_correlation_id TEXT;
BEGIN
  IF p_game_day < 0 THEN RAISE EXCEPTION 'Game day must be non-negative'; END IF;

  UPDATE technology_license_contracts
  SET status = 'EXPIRED'
  WHERE status = 'ACTIVE'
    AND effective_to_game_day IS NOT NULL
    AND effective_to_game_day < p_game_day;

  FOR v_contract IN
    SELECT c.* FROM technology_license_contracts c
    WHERE c.status = 'ACTIVE'
      AND c.daily_fee_units > 0
      AND c.effective_from_game_day <= p_game_day
      AND (c.effective_to_game_day IS NULL OR c.effective_to_game_day >= p_game_day)
      AND c.paid_through_game_day < p_game_day
    ORDER BY c.id FOR UPDATE
  LOOP
    SELECT a.id, a.balance INTO v_debit_account, v_balance
    FROM economic_accounts a
    WHERE a.owner_economic_id = v_contract.licensee_economic_id
      AND a.asset_id = 1 AND a.status = 'active' AND a.is_default_settlement
    ORDER BY a.id LIMIT 1 FOR UPDATE;
    SELECT a.id INTO v_credit_account
    FROM economic_accounts a
    WHERE a.owner_economic_id = v_contract.licensor_economic_id
      AND a.asset_id = 1 AND a.status = 'active' AND a.is_default_settlement
    ORDER BY a.id LIMIT 1 FOR UPDATE;

    IF v_debit_account IS NULL OR v_credit_account IS NULL
       OR COALESCE(v_balance, 0) < v_contract.daily_fee_units THEN CONTINUE; END IF;

    v_correlation_id := 'ip-license-daily:' || v_contract.id || ':' || p_game_day;
    SELECT e.transaction_id INTO v_transaction_id
    FROM economic_transactions e WHERE e.correlation_id = v_correlation_id;
    IF v_transaction_id IS NULL THEN
      SELECT e.transaction_id INTO v_transaction_id
      FROM earth_post_transaction(
        v_correlation_id, p_game_day, 1439, 'IP_LICENSE_DAILY',
        'TECHNOLOGY_LICENSE', v_contract.id, v_contract.rules_version,
        jsonb_build_array(
          jsonb_build_object('account_id', v_debit_account, 'delta', -v_contract.daily_fee_units, 'reason_code', 'IP_LICENSE_DAILY'),
          jsonb_build_object('account_id', v_credit_account, 'delta', v_contract.daily_fee_units, 'reason_code', 'IP_LICENSE_DAILY')
        )
      ) e;
    END IF;

    INSERT INTO technology_license_payments (contract_id, game_day, amount_units, transaction_id, correlation_id)
    VALUES (v_contract.id, p_game_day, v_contract.daily_fee_units, v_transaction_id, v_correlation_id)
    ON CONFLICT (contract_id, game_day) DO NOTHING;
    UPDATE technology_license_contracts
    SET paid_through_game_day = p_game_day, last_daily_transaction_id = v_transaction_id
    WHERE id = v_contract.id;
    v_paid := v_paid + 1;
  END LOOP;
  RETURN v_paid;
END;
$$;

COMMENT ON FUNCTION earth_settle_technology_license_fees(BIGINT) IS
  'Posts one idempotent Economy V2 IP_LICENSE_DAILY transfer per payable active contract.';
