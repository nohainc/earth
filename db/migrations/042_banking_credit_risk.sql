-- EARTH ACTIVE MIGRATION: source-backed banking credit and risk history

ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS bank_economic_id TEXT REFERENCES owner_registry(economic_id);
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS credit_limit_units BIGINT NOT NULL DEFAULT 0 CHECK (credit_limit_units >= 0);
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS term_days INTEGER NOT NULL DEFAULT 30 CHECK (term_days > 0);
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS origination_game_day BIGINT NOT NULL DEFAULT 1;
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS maturity_game_day BIGINT NOT NULL DEFAULT 1;
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS next_payment_game_day BIGINT NOT NULL DEFAULT 1;
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS delinquent_since_game_day BIGINT;
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS defaulted_game_day BIGINT;

CREATE TABLE IF NOT EXISTS bank_credit_policies (
  id TEXT PRIMARY KEY,
  bank_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  policy_version TEXT NOT NULL,
  max_term_days INTEGER NOT NULL CHECK (max_term_days > 0),
  base_rate_bps INTEGER NOT NULL CHECK (base_rate_bps >= 0),
  max_loan_to_collateral_bps INTEGER NOT NULL CHECK (max_loan_to_collateral_bps BETWEEN 0 AND 10000),
  max_loan_to_cashflow_bps INTEGER NOT NULL CHECK (max_loan_to_cashflow_bps >= 0),
  minimum_reserve_ratio_bps INTEGER NOT NULL CHECK (minimum_reserve_ratio_bps BETWEEN 0 AND 10000),
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED')),
  UNIQUE (bank_economic_id, policy_version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE TABLE IF NOT EXISTS bank_loan_collateral (
  id TEXT PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id),
  owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  collateral_type TEXT NOT NULL CHECK (collateral_type IN ('CASH','ASSET_POSITION','CONTRACT_RIGHT','GUARANTEE')),
  reference_id TEXT NOT NULL,
  valuation_units BIGINT NOT NULL CHECK (valuation_units > 0),
  haircut_bps INTEGER NOT NULL CHECK (haircut_bps BETWEEN 0 AND 10000),
  status TEXT NOT NULL DEFAULT 'PLEDGED' CHECK (status IN ('PLEDGED','RELEASED','LIQUIDATED')),
  pledged_game_day BIGINT NOT NULL,
  released_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS bank_loan_collateral_loan_idx ON bank_loan_collateral (loan_id, status);

CREATE TABLE IF NOT EXISTS bank_loan_guarantees (
  id TEXT PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id),
  guarantor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  guaranteed_units BIGINT NOT NULL CHECK (guaranteed_units > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CALLED','RELEASED')),
  created_game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS bank_loan_guarantees_loan_idx ON bank_loan_guarantees (loan_id, status);

CREATE TABLE IF NOT EXISTS bank_loan_payments (
  id TEXT PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  principal_units BIGINT NOT NULL CHECK (principal_units >= 0),
  interest_units BIGINT NOT NULL CHECK (interest_units >= 0),
  payment_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK (principal_units + interest_units = amount_units)
);

CREATE TABLE IF NOT EXISTS bank_loan_resolutions (
  id TEXT PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id),
  resolution_type TEXT NOT NULL CHECK (resolution_type IN ('DELINQUENCY','RESTRUCTURE','GUARANTEE_CALL','LIQUIDATION','WRITE_OFF','CURED')),
  claim_units BIGINT NOT NULL CHECK (claim_units >= 0),
  recovered_units BIGINT NOT NULL DEFAULT 0 CHECK (recovered_units >= 0),
  priority_rank INTEGER NOT NULL CHECK (priority_rank > 0),
  game_day BIGINT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object'),
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS bank_loan_resolutions_loan_day_idx ON bank_loan_resolutions (loan_id, game_day DESC);

CREATE UNIQUE INDEX IF NOT EXISTS bank_credit_policies_one_active_idx
  ON bank_credit_policies (bank_economic_id)
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;

INSERT INTO bank_credit_policies (
  id, bank_economic_id, policy_version, max_term_days, base_rate_bps,
  max_loan_to_collateral_bps, max_loan_to_cashflow_bps,
  minimum_reserve_ratio_bps, effective_from_game_day
)
VALUES ('BANK-POLICY-GLOBAL-V1', 'ECON-GLOBAL-BANK-001', 'global-bank-credit-v1', 180, 700, 5000, 6000, 2000, 1)
ON CONFLICT (id) DO NOTHING;
