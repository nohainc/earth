-- Finance V2 Plan 9: set-based daily bank settlement.

CREATE TABLE IF NOT EXISTS bank_settlement_journals (
  game_day BIGINT PRIMARY KEY,
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  loans_accrued BIGINT NOT NULL DEFAULT 0,
  deposits_accrued BIGINT NOT NULL DEFAULT 0,
  loan_payments BIGINT NOT NULL DEFAULT 0,
  deposit_payouts BIGINT NOT NULL DEFAULT 0,
  loan_payment_units BIGINT NOT NULL DEFAULT 0,
  deposit_payout_units BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL CHECK (status IN ('COMPLETED', 'LIQUIDITY_CONSTRAINED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION earth_settle_v2_global_bank(
  p_game_day BIGINT,
  p_game_minute SMALLINT DEFAULT 1439
)
RETURNS TABLE (
  status TEXT,
  economic_transaction_id BIGINT,
  loans_accrued BIGINT,
  deposits_accrued BIGINT,
  loan_payments BIGINT,
  deposit_payouts BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  prior bank_settlement_journals;
  bank_account BIGINT;
  bank_balance BIGINT;
  available_for_deposits BIGINT;
  effects JSONB;
  posting RECORD;
  loan_count BIGINT;
  deposit_count BIGINT;
  paid_loan_count BIGINT;
  paid_deposit_count BIGINT;
  paid_loan_units BIGINT;
  paid_deposit_units BIGINT;
  accrued_loans BIGINT;
  accrued_deposits BIGINT;
  settlement_status TEXT := 'COMPLETED';
BEGIN
  SELECT * INTO prior FROM bank_settlement_journals WHERE game_day = p_game_day;
  IF FOUND THEN
    status := prior.status;
    economic_transaction_id := prior.economic_transaction_id;
    loans_accrued := prior.loans_accrued;
    deposits_accrued := prior.deposits_accrued;
    loan_payments := prior.loan_payments;
    deposit_payouts := prior.deposit_payouts;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT a.id, a.balance INTO bank_account, bank_balance
  FROM economic_accounts a
  JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  WHERE o.id = 'SYSTEM-GLOBAL-BANK'
    AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active'
  ORDER BY a.id
  LIMIT 1
  FOR UPDATE;
  IF bank_account IS NULL THEN RAISE EXCEPTION 'Global Bank V2 reserve account is unavailable'; END IF;

  SELECT loans_updated, deposits_updated INTO accrued_loans, accrued_deposits
  FROM earth_accrue_bank_interest(p_game_day);

  CREATE TEMP TABLE v2_bank_effects (
    account_id BIGINT PRIMARY KEY,
    delta BIGINT NOT NULL,
    reason_code TEXT NOT NULL
  ) ON COMMIT DROP;
  CREATE TEMP TABLE v2_bank_loan_due ON COMMIT DROP AS
  SELECT l.id, l.borrower_economic_id, l.borrower_type,
         l.accrued_interest_units, l.outstanding_principal_units,
         l.remaining_installments, l.installment_interval_days,
         l.next_payment_game_day, a.id AS borrower_account_id,
         COALESCE(a.balance, 0)::BIGINT AS borrower_balance,
         CASE WHEN l.remaining_installments > 0
           THEN LEAST(l.outstanding_principal_units,
             (l.outstanding_principal_units + l.remaining_installments - 1) / l.remaining_installments)
           ELSE 0 END AS scheduled_principal_units
  FROM bank_loans l
  LEFT JOIN economic_accounts a
    ON a.owner_economic_id = l.borrower_economic_id
   AND a.asset_id = 1
   AND a.account_type = CASE WHEN l.borrower_type = 'human' THEN 1 ELSE 3 END
   AND a.is_default_settlement
   AND a.status = 'active'
  WHERE l.status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED')
    AND COALESCE(l.next_payment_game_day, p_game_day) <= p_game_day
    AND l.outstanding_principal_units + l.accrued_interest_units > 0
  FOR UPDATE OF l;

  SELECT COUNT(*) INTO loan_count FROM v2_bank_loan_due;
  PERFORM 1
  FROM economic_accounts a
  JOIN v2_bank_loan_due d ON d.borrower_account_id = a.id
  ORDER BY a.id
  FOR UPDATE;
  SELECT COUNT(*) INTO paid_loan_count FROM v2_bank_loan_due
  WHERE LEAST(accrued_interest_units + outstanding_principal_units,
              accrued_interest_units + scheduled_principal_units,
              borrower_balance) > 0;
  SELECT COALESCE(SUM(LEAST(accrued_interest_units + outstanding_principal_units,
                            accrued_interest_units + scheduled_principal_units,
                            borrower_balance)), 0)
    INTO paid_loan_units FROM v2_bank_loan_due;

  INSERT INTO v2_bank_effects(account_id, delta, reason_code)
  SELECT borrower_account_id, -SUM(paid_units), 'BANK_LOAN_PAYMENT'
  FROM (
    SELECT borrower_account_id,
           LEAST(accrued_interest_units + outstanding_principal_units,
                 accrued_interest_units + scheduled_principal_units,
                 borrower_balance) AS paid_units
    FROM v2_bank_loan_due
    WHERE borrower_account_id IS NOT NULL
  ) paid
  WHERE paid_units > 0
  GROUP BY borrower_account_id
  ON CONFLICT (account_id) DO UPDATE SET delta = v2_bank_effects.delta + EXCLUDED.delta;

  INSERT INTO v2_bank_effects(account_id, delta, reason_code)
  VALUES (bank_account, paid_loan_units, 'BANK_LOAN_PAYMENT')
  ON CONFLICT (account_id) DO UPDATE SET delta = v2_bank_effects.delta + EXCLUDED.delta;

  available_for_deposits := bank_balance + paid_loan_units;
  CREATE TEMP TABLE v2_bank_deposit_due ON COMMIT DROP AS
  WITH due AS (
    SELECT d.id, d.depositor_economic_id, d.principal_units + d.accrued_interest_units AS payout_units,
           a.id AS depositor_account_id
    FROM bank_deposits d
    LEFT JOIN economic_accounts a
      ON a.owner_economic_id = d.depositor_economic_id
     AND a.asset_id = 1 AND a.account_type = 1
     AND a.is_default_settlement AND a.status = 'active'
    WHERE d.status IN ('ACTIVE', 'MATURED')
      AND d.maturity_total_game_minute <= ((p_game_day - 1) * 1440 + p_game_minute)
    ORDER BY d.id
  )
  SELECT *, SUM(payout_units) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_units
  FROM due;

  SELECT COUNT(*) INTO deposit_count FROM v2_bank_deposit_due;
  SELECT COUNT(*) INTO paid_deposit_count FROM v2_bank_deposit_due
  WHERE cumulative_units <= available_for_deposits AND depositor_account_id IS NOT NULL;
  SELECT COALESCE(SUM(payout_units) FILTER (WHERE cumulative_units <= available_for_deposits AND depositor_account_id IS NOT NULL), 0)
    INTO paid_deposit_units FROM v2_bank_deposit_due;
  IF paid_deposit_count < deposit_count THEN settlement_status := 'LIQUIDITY_CONSTRAINED'; END IF;

  INSERT INTO v2_bank_effects(account_id, delta, reason_code)
  SELECT depositor_account_id, SUM(payout_units), 'BANK_DEPOSIT_PAYOUT'
  FROM v2_bank_deposit_due
  WHERE cumulative_units <= available_for_deposits AND depositor_account_id IS NOT NULL
  GROUP BY depositor_account_id
  ON CONFLICT (account_id) DO UPDATE SET delta = v2_bank_effects.delta + EXCLUDED.delta;
  INSERT INTO v2_bank_effects(account_id, delta, reason_code)
  VALUES (bank_account, -paid_deposit_units, 'BANK_DEPOSIT_PAYOUT')
  ON CONFLICT (account_id) DO UPDATE SET delta = v2_bank_effects.delta + EXCLUDED.delta;

  SELECT jsonb_agg(jsonb_build_object('account_id', account_id, 'delta', delta, 'reason_code', reason_code) ORDER BY account_id)
    INTO effects FROM v2_bank_effects WHERE delta <> 0;
  IF effects IS NOT NULL AND jsonb_array_length(effects) >= 2 THEN
    SELECT * INTO posting FROM earth_post_settlement_batch(
      format('bank-settlement:%s', p_game_day), p_game_day, p_game_minute,
      'global_bank', 'SYSTEM-GLOBAL-BANK', 'global-bank-v2', effects
    );
    economic_transaction_id := posting.transaction_id;
  END IF;

  INSERT INTO bank_loan_payments (loan_id, transaction_id, correlation_id, payment_units, interest_units, principal_units, game_day)
  SELECT d.id, economic_transaction_id, format('bank-settlement:loan:%s:%s', d.id, p_game_day),
         paid_units, LEAST(paid_units, d.accrued_interest_units), paid_units - LEAST(paid_units, d.accrued_interest_units), p_game_day
  FROM (
    SELECT d.*, LEAST(d.accrued_interest_units + d.outstanding_principal_units,
                      d.accrued_interest_units + d.scheduled_principal_units,
                      d.borrower_balance) AS paid_units
    FROM v2_bank_loan_due d
  ) d
  WHERE paid_units > 0;
  UPDATE bank_loans l SET
    accrued_interest_units = l.accrued_interest_units - LEAST(d.paid_units, l.accrued_interest_units),
    outstanding_principal_units = l.outstanding_principal_units - (d.paid_units - LEAST(d.paid_units, l.accrued_interest_units)),
    remaining_installments = CASE WHEN d.paid_units >= d.accrued_interest_units + d.scheduled_principal_units AND d.scheduled_principal_units > 0 THEN GREATEST(0, l.remaining_installments - 1) ELSE l.remaining_installments END,
    next_payment_game_day = CASE WHEN d.paid_units >= d.accrued_interest_units + d.scheduled_principal_units THEN p_game_day + l.installment_interval_days ELSE p_game_day + 1 END,
    status = CASE WHEN l.outstanding_principal_units - (d.paid_units - LEAST(d.paid_units, l.accrued_interest_units)) = 0 THEN 'REPAID' ELSE l.status END,
    updated_at = CURRENT_TIMESTAMP
  FROM (
    SELECT d.*, LEAST(d.accrued_interest_units + d.outstanding_principal_units,
                      d.accrued_interest_units + d.scheduled_principal_units,
                      d.borrower_balance) AS paid_units
    FROM v2_bank_loan_due d
  ) d WHERE l.id = d.id AND d.paid_units > 0;

  UPDATE bank_deposits d SET status = CASE WHEN due.cumulative_units <= available_for_deposits AND due.depositor_account_id IS NOT NULL THEN 'WITHDRAWN' ELSE 'MATURED' END,
    payout_transaction_id = CASE WHEN due.cumulative_units <= available_for_deposits AND due.depositor_account_id IS NOT NULL THEN economic_transaction_id ELSE d.payout_transaction_id END,
    updated_at = CURRENT_TIMESTAMP
  FROM v2_bank_deposit_due due WHERE d.id = due.id;

  INSERT INTO bank_settlement_journals (
    game_day, economic_transaction_id, loans_accrued, deposits_accrued, loan_payments, deposit_payouts,
    loan_payment_units, deposit_payout_units, status
  ) VALUES (
    p_game_day, economic_transaction_id, accrued_loans, accrued_deposits, paid_loan_count, paid_deposit_count,
    paid_loan_units, paid_deposit_units, settlement_status
  );
  SELECT settlement_status, economic_transaction_id, accrued_loans, accrued_deposits, paid_loan_count, paid_deposit_count
    INTO status, economic_transaction_id, loans_accrued, deposits_accrued, loan_payments, deposit_payouts;
  RETURN NEXT;
END;
$$;
