-- Bank mutations are database-owned. The client supplies only amount, term,
-- and an idempotency key; the database owns time, balances, and lifecycle.

CREATE OR REPLACE FUNCTION earth_create_bank_deposit(
  p_deposit_id TEXT,
  p_human_id TEXT,
  p_amount NUMERIC(20,2),
  p_term_days INTEGER,
  p_correlation_id TEXT
)
RETURNS global_bank_deposits
LANGUAGE plpgsql
AS $$
DECLARE
  v_deposit global_bank_deposits%ROWTYPE;
  v_account account_balances%ROWTYPE;
  v_time RECORD;
BEGIN
  SELECT * INTO v_deposit FROM global_bank_deposits WHERE id = p_deposit_id;
  IF FOUND THEN RETURN v_deposit; END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Deposit amount must be positive';
  END IF;
  IF p_term_days IS NULL OR p_term_days < 1 OR p_term_days > 90 THEN
    RAISE EXCEPTION 'Deposit term must be between 1 and 90 game days';
  END IF;
  IF p_correlation_id IS NULL OR LENGTH(TRIM(p_correlation_id)) = 0 THEN
    RAISE EXCEPTION 'Deposit correlation ID is required';
  END IF;

  SELECT * INTO v_account
  FROM account_balances
  WHERE owner_id = p_human_id AND currency = 'CREDIT'
  FOR UPDATE;
  IF NOT FOUND OR v_account.balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient Credits for deposit';
  END IF;

  SELECT * INTO v_time FROM earth_get_current_game_time();

  PERFORM earth_transfer_credits(
    gen_random_uuid(), v_time.game_day, v_account.account_id,
    'account-global-corporate-bank', p_amount, 'bank_deposit',
    p_deposit_id, 'global-bank-v1', p_correlation_id
  );

  INSERT INTO global_bank_deposits (
    id, human_id, principal, daily_rate, start_game_day, start_game_minute,
    maturity_game_day, maturity_game_minute, last_settled_game_day
  ) VALUES (
    p_deposit_id, p_human_id, p_amount, 0.001,
    v_time.game_day, v_time.game_minute,
    v_time.game_day + p_term_days, v_time.game_minute, v_time.game_day
  ) RETURNING * INTO v_deposit;

  RETURN v_deposit;
END;
$$;

CREATE OR REPLACE FUNCTION earth_withdraw_bank_deposit(
  p_human_id TEXT,
  p_deposit_id TEXT,
  p_correlation_id TEXT
)
RETURNS TABLE (
  deposit_id TEXT,
  principal NUMERIC(20,2),
  interest NUMERIC(20,2),
  payout NUMERIC(20,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_deposit global_bank_deposits%ROWTYPE;
  v_bank account_balances%ROWTYPE;
  v_account account_balances%ROWTYPE;
  v_time RECORD;
  v_current_minute BIGINT;
  v_maturity_minute BIGINT;
  v_payout NUMERIC(20,2);
BEGIN
  SELECT * INTO v_deposit
  FROM global_bank_deposits
  WHERE id = p_deposit_id AND human_id = p_human_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bank deposit not found'; END IF;
  IF v_deposit.status NOT IN ('active', 'matured') THEN
    RAISE EXCEPTION 'Bank deposit is not withdrawable';
  END IF;

  SELECT * INTO v_time FROM earth_get_current_game_time();
  v_current_minute := (v_time.game_day - 1) * 1440 + v_time.game_minute;
  v_maturity_minute := (v_deposit.maturity_game_day - 1) * 1440
    + COALESCE(v_deposit.maturity_game_minute, 0);
  IF v_current_minute < v_maturity_minute THEN
    RAISE EXCEPTION 'Deposit has not reached maturity';
  END IF;

  v_payout := v_deposit.principal + v_deposit.accrued_interest;
  SELECT * INTO v_bank
  FROM account_balances
  WHERE account_id = 'account-global-corporate-bank' AND currency = 'CREDIT'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Global bank account is unavailable; apply the bank migration first'; END IF;
  IF v_bank.balance < v_payout THEN
    RAISE EXCEPTION 'Global bank cannot settle this payout yet; bank income has not funded the required balance';
  END IF;

  SELECT * INTO v_account
  FROM account_balances
  WHERE owner_id = p_human_id AND currency = 'CREDIT'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit account not found'; END IF;

  PERFORM earth_transfer_credits(
    gen_random_uuid(), v_time.game_day, 'account-global-corporate-bank',
    v_account.account_id, v_payout, 'bank_withdrawal', p_deposit_id,
    'global-bank-v1', p_correlation_id
  );

  UPDATE global_bank_deposits
  SET status = 'withdrawn', last_settled_game_day = v_time.game_day,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_deposit_id;

  RETURN QUERY SELECT v_deposit.id, v_deposit.principal,
    v_deposit.accrued_interest, v_payout;
END;
$$;
