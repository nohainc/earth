-- Finance V2 Plan 6: loans are bank assets funded by existing liquidity.

CREATE TABLE IF NOT EXISTS bank_loans (
  id TEXT PRIMARY KEY,
  borrower_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  borrower_type TEXT NOT NULL CHECK (borrower_type IN ('human', 'city', 'corporation')),
  original_principal_units BIGINT NOT NULL CHECK (original_principal_units > 0),
  outstanding_principal_units BIGINT NOT NULL CHECK (outstanding_principal_units >= 0),
  accrued_interest_units BIGINT NOT NULL DEFAULT 0 CHECK (accrued_interest_units >= 0),
  rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0 AND rate_bps <= 5000),
  rate_rule_version TEXT NOT NULL,
  origination_total_game_minute BIGINT NOT NULL CHECK (origination_total_game_minute >= 0),
  installment_interval_days INTEGER NOT NULL DEFAULT 1 CHECK (installment_interval_days > 0),
  next_payment_game_day BIGINT,
  remaining_installments INTEGER NOT NULL DEFAULT 0 CHECK (remaining_installments >= 0),
  grace_period_days INTEGER NOT NULL DEFAULT 0 CHECK (grace_period_days >= 0),
  max_missed_payments INTEGER NOT NULL DEFAULT 3 CHECK (max_missed_payments >= 0),
  status TEXT NOT NULL DEFAULT 'CURRENT' CHECK (status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'DEFAULTED', 'RESTRUCTURED', 'REPAID', 'WRITTEN_OFF')),
  origination_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS bank_loans_borrower_status_idx ON bank_loans(borrower_economic_id, status);
CREATE INDEX IF NOT EXISTS bank_loans_payment_idx ON bank_loans(status, next_payment_game_day);

CREATE OR REPLACE FUNCTION earth_originate_v2_bank_loan(
  p_loan_id TEXT,
  p_borrower_id TEXT,
  p_principal_units BIGINT,
  p_term_installments INTEGER,
  p_correlation_id TEXT,
  p_rate_bps INTEGER DEFAULT 500,
  p_rate_rule_version TEXT DEFAULT 'global-bank-v2',
  p_installment_interval_days INTEGER DEFAULT 1
)
RETURNS bank_loans
LANGUAGE plpgsql
AS $$
DECLARE
  loan bank_loans;
  transaction_row RECORD;
  borrower RECORD;
  world RECORD;
  bank_account BIGINT;
  borrower_account BIGINT;
  reserve_units BIGINT;
  deposit_liabilities_units BIGINT;
  start_minute BIGINT;
BEGIN
  SELECT * INTO loan FROM bank_loans WHERE correlation_id = p_correlation_id OR id = p_loan_id;
  IF FOUND THEN RETURN loan; END IF;
  IF p_principal_units IS NULL OR p_principal_units <= 0 THEN RAISE EXCEPTION 'Loan principal must be positive'; END IF;
  IF p_term_installments IS NULL OR p_term_installments < 1 OR p_term_installments > 360 THEN RAISE EXCEPTION 'Loan term is outside supported bounds'; END IF;
  IF p_installment_interval_days IS NULL OR p_installment_interval_days < 1 THEN RAISE EXCEPTION 'Loan installment interval must be positive'; END IF;

  SELECT o.economic_id, o.owner_type INTO borrower FROM owner_registry o WHERE o.id = p_borrower_id AND o.owner_type IN ('city', 'corporation') AND o.status = 'active';
  IF borrower.economic_id IS NULL THEN
    SELECT o.economic_id, 'house'::TEXT INTO borrower
      FROM humans h JOIN owner_registry o ON o.id = h.house_id
     WHERE h.id = p_borrower_id AND o.owner_type = 'house' AND o.status = 'active';
  END IF;
  SELECT a.id INTO borrower_account
  FROM economic_accounts a WHERE a.owner_economic_id = borrower.economic_id AND a.asset_id = 1
    AND a.account_type = CASE WHEN borrower.owner_type IN ('human', 'house') THEN 1 ELSE 3 END
    AND a.is_default_settlement AND a.status = 'active';
  SELECT a.id INTO bank_account FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active';
  IF borrower_account IS NULL OR bank_account IS NULL THEN RAISE EXCEPTION 'V2 borrower or bank reserve account is unavailable'; END IF;

  SELECT balance INTO reserve_units FROM economic_accounts WHERE id = bank_account FOR UPDATE;
  SELECT COALESCE(SUM(principal_units + accrued_interest_units), 0) INTO deposit_liabilities_units
  FROM bank_deposits WHERE status IN ('ACTIVE', 'MATURED');
  IF reserve_units - deposit_liabilities_units < p_principal_units THEN
    RAISE EXCEPTION 'Global bank lacks lendable liquidity for this loan';
  END IF;

  SELECT game_day, game_minute INTO world FROM world_state WHERE id = 'WORLD';
  start_minute := (world.game_day - 1) * 1440 + world.game_minute;
  SELECT * INTO transaction_row FROM earth_post_transaction(
    p_correlation_id, world.game_day, world.game_minute, 'bank_loan_origination', 'global_bank', p_loan_id, p_rate_rule_version,
    jsonb_build_array(
      jsonb_build_object('account_id', bank_account, 'delta', -p_principal_units, 'reason_code', 'BANK_LOAN_FUNDING'),
      jsonb_build_object('account_id', borrower_account, 'delta', p_principal_units, 'reason_code', 'BANK_LOAN_FUNDING')
    )
  );

  INSERT INTO bank_loans (
    id, borrower_economic_id, borrower_type, original_principal_units, outstanding_principal_units,
    rate_bps, rate_rule_version, origination_total_game_minute, installment_interval_days,
    next_payment_game_day, remaining_installments, origination_transaction_id, correlation_id
  ) VALUES (
    p_loan_id, borrower.economic_id, borrower.owner_type, p_principal_units, p_principal_units,
    p_rate_bps, p_rate_rule_version, start_minute, p_installment_interval_days,
    world.game_day + p_installment_interval_days, p_term_installments, transaction_row.transaction_id, p_correlation_id
  ) RETURNING * INTO loan;
  RETURN loan;
END;
$$;
