-- Finance V2 Plan 20: deposit protection is an explicit fiscal liability.

CREATE TABLE IF NOT EXISTS deposit_protection_rules (
  id TEXT PRIMARY KEY,
  protection_limit_units BIGINT NOT NULL CHECK (protection_limit_units >= 0),
  rule_version TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUPERSEDED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS deposit_protection_one_active_idx ON deposit_protection_rules(status) WHERE status = 'ACTIVE';
INSERT INTO deposit_protection_rules (id, protection_limit_units, rule_version, effective_from_game_day)
VALUES ('DEPOSIT-PROTECTION-DEFAULT', 10000, 'deposit-protection-v1', 0)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE bank_deposits ADD COLUMN IF NOT EXISTS deposit_protection_limit_units BIGINT NOT NULL DEFAULT 10000;
ALTER TABLE bank_deposits ADD COLUMN IF NOT EXISTS deposit_protection_rule_version TEXT NOT NULL DEFAULT 'deposit-protection-v1';

CREATE TABLE IF NOT EXISTS deposit_protection_claims (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deposit_id TEXT NOT NULL REFERENCES bank_deposits(id),
  depositor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  protection_limit_units BIGINT NOT NULL,
  insured_amount_units BIGINT NOT NULL CHECK (insured_amount_units >= 0),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PAID','PARTIAL','UNFUNDED','CANCELLED')),
  fiscal_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION earth_prepare_deposit_protection_claims(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE inserted_count BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM global_bank_resolution_state WHERE id = 1 AND status IN ('INSOLVENT','RESOLUTION')) THEN RETURN 0; END IF;
  INSERT INTO deposit_protection_claims (deposit_id, depositor_economic_id, protection_limit_units, insured_amount_units, correlation_id)
    SELECT d.id, d.depositor_economic_id, d.deposit_protection_limit_units,
      LEAST(d.deposit_protection_limit_units, d.principal_units + d.accrued_interest_units),
      'deposit-protection:' || d.id
    FROM bank_deposits d
    WHERE d.status IN ('ACTIVE','MATURED')
    ON CONFLICT (correlation_id) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;
