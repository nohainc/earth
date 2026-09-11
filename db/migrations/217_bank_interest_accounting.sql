-- Finance V2 Plan 7: accrue claims separately from actual CREDIT movement.

ALTER TABLE bank_deposits ADD COLUMN IF NOT EXISTS last_interest_game_day BIGINT;
ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS last_interest_game_day BIGINT;

CREATE TABLE IF NOT EXISTS bank_loan_payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id),
  transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  payment_units BIGINT NOT NULL CHECK (payment_units > 0),
  interest_units BIGINT NOT NULL CHECK (interest_units >= 0),
  principal_units BIGINT NOT NULL CHECK (principal_units >= 0),
  game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION earth_accrue_bank_interest(p_game_day BIGINT)
RETURNS TABLE(loans_updated BIGINT, deposits_updated BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE bank_loans
     SET accrued_interest_units = accrued_interest_units + ((outstanding_principal_units * rate_bps) / 10000),
         last_interest_game_day = p_game_day,
         updated_at = CURRENT_TIMESTAMP
   WHERE status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED')
     AND COALESCE(last_interest_game_day, -1) < p_game_day;
  GET DIAGNOSTICS loans_updated = ROW_COUNT;

  UPDATE bank_deposits
     SET accrued_interest_units = accrued_interest_units + ((principal_units * rate_bps) / 10000),
         last_interest_game_day = p_game_day,
         updated_at = CURRENT_TIMESTAMP
   WHERE status IN ('ACTIVE', 'MATURED')
     AND COALESCE(last_interest_game_day, -1) < p_game_day;
  GET DIAGNOSTICS deposits_updated = ROW_COUNT;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION earth_pay_v2_bank_loan(
  p_loan_id TEXT,
  p_amount_units BIGINT,
  p_correlation_id TEXT
)
RETURNS bank_loan_payments
LANGUAGE plpgsql
AS $$
DECLARE
  loan bank_loans;
  payment bank_loan_payments;
  world RECORD;
  borrower_account BIGINT;
  bank_account BIGINT;
  transaction_row RECORD;
  interest_paid BIGINT;
  principal_paid BIGINT;
BEGIN
  SELECT * INTO payment FROM bank_loan_payments WHERE correlation_id = p_correlation_id;
  IF FOUND THEN RETURN payment; END IF;
  SELECT * INTO loan FROM bank_loans WHERE id = p_loan_id AND status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payable bank loan not found'; END IF;
  IF p_amount_units IS NULL OR p_amount_units <= 0 THEN RAISE EXCEPTION 'Loan payment must be positive'; END IF;
  IF p_amount_units > loan.accrued_interest_units + loan.outstanding_principal_units THEN RAISE EXCEPTION 'Loan payment exceeds amount owed'; END IF;

  SELECT a.id INTO borrower_account FROM economic_accounts a
  WHERE a.owner_economic_id = loan.borrower_economic_id AND a.asset_id = 1
    AND a.account_type = CASE WHEN loan.borrower_type = 'human' THEN 1 ELSE 3 END
    AND a.is_default_settlement AND a.status = 'active';
  SELECT a.id INTO bank_account FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active';
  IF borrower_account IS NULL OR bank_account IS NULL THEN RAISE EXCEPTION 'V2 loan payment account is unavailable'; END IF;
  interest_paid := LEAST(p_amount_units, loan.accrued_interest_units);
  principal_paid := p_amount_units - interest_paid;
  SELECT game_day, game_minute INTO world FROM world_state WHERE id = 'WORLD';
  SELECT * INTO transaction_row FROM earth_post_transaction(
    p_correlation_id, world.game_day, world.game_minute, 'bank_loan_payment', 'global_bank', p_loan_id, 'global-bank-v2',
    jsonb_build_array(
      jsonb_build_object('account_id', borrower_account, 'delta', -p_amount_units, 'reason_code', 'BANK_LOAN_PAYMENT'),
      jsonb_build_object('account_id', bank_account, 'delta', p_amount_units, 'reason_code', 'BANK_LOAN_PAYMENT')
    )
  );
  INSERT INTO bank_loan_payments (loan_id, transaction_id, correlation_id, payment_units, interest_units, principal_units, game_day)
  VALUES (p_loan_id, transaction_row.transaction_id, p_correlation_id, p_amount_units, interest_paid, principal_paid, world.game_day)
  RETURNING * INTO payment;
  UPDATE bank_loans SET accrued_interest_units = accrued_interest_units - interest_paid,
    outstanding_principal_units = outstanding_principal_units - principal_paid,
    status = CASE WHEN outstanding_principal_units - principal_paid = 0 THEN 'REPAID' ELSE status END,
    updated_at = CURRENT_TIMESTAMP WHERE id = p_loan_id;
  RETURN payment;
END;
$$;

CREATE OR REPLACE FUNCTION earth_withdraw_v2_bank_deposit(
  p_deposit_id TEXT,
  p_human_id TEXT,
  p_correlation_id TEXT
)
RETURNS bank_deposits
LANGUAGE plpgsql
AS $$
DECLARE
  deposit bank_deposits;
  world RECORD;
  depositor_account BIGINT;
  bank_account BIGINT;
  transaction_row RECORD;
  current_minute BIGINT;
  payout_units BIGINT;
BEGIN
  SELECT d.* INTO deposit FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
  WHERE d.id = p_deposit_id AND o.id = p_human_id AND d.status IN ('ACTIVE', 'MATURED') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawable V2 bank deposit not found'; END IF;
  SELECT game_day, game_minute INTO world FROM world_state WHERE id = 'WORLD';
  current_minute := (world.game_day - 1) * 1440 + world.game_minute;
  IF current_minute < deposit.maturity_total_game_minute AND NOT deposit.early_withdrawal_allowed THEN RAISE EXCEPTION 'Deposit has not reached maturity'; END IF;
  payout_units := deposit.principal_units + deposit.accrued_interest_units;
  SELECT a.id INTO depositor_account FROM economic_accounts a WHERE a.owner_economic_id = deposit.depositor_economic_id AND a.asset_id = 1 AND a.account_type = 1 AND a.is_default_settlement AND a.status = 'active';
  SELECT a.id INTO bank_account FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active';
  IF depositor_account IS NULL OR bank_account IS NULL THEN RAISE EXCEPTION 'V2 deposit payout account is unavailable'; END IF;
  SELECT * INTO transaction_row FROM earth_post_transaction(
    p_correlation_id, world.game_day, world.game_minute, 'bank_deposit_withdrawal', 'global_bank', p_deposit_id, 'global-bank-v2',
    jsonb_build_array(
      jsonb_build_object('account_id', bank_account, 'delta', -payout_units, 'reason_code', 'BANK_DEPOSIT_PAYOUT'),
      jsonb_build_object('account_id', depositor_account, 'delta', payout_units, 'reason_code', 'BANK_DEPOSIT_PAYOUT')
    )
  );
  UPDATE bank_deposits SET status = 'WITHDRAWN', payout_transaction_id = transaction_row.transaction_id, updated_at = CURRENT_TIMESTAMP WHERE id = p_deposit_id;
  SELECT * INTO deposit FROM bank_deposits WHERE id = p_deposit_id;
  RETURN deposit;
END;
$$;
