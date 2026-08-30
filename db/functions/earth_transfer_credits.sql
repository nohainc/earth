-- Stored Function: earth_transfer_credits
--
-- Narrow financial primitive: keeps balance mutations and their ledger audit
-- entry atomic in a single PostgreSQL transaction.
CREATE OR REPLACE FUNCTION earth_transfer_credits(
  p_ledger_id UUID,
  p_game_day BIGINT,
  p_debit_account TEXT,
  p_credit_account TEXT,
  p_amount NUMERIC(20,2),
  p_reason_type TEXT,
  p_reason_id TEXT,
  p_rule_version TEXT,
  p_correlation_id TEXT
)
RETURNS TABLE (
  status TEXT,
  ledger_id UUID,
  amount NUMERIC(20,2),
  already_processed BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
  account_count INTEGER;
BEGIN
  IF p_debit_account IS NULL OR p_credit_account IS NULL OR p_debit_account = p_credit_account THEN
    RAISE EXCEPTION 'Credit transfer requires two different accounts';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Credit transfer amount must be positive';
  END IF;

  IF p_reason_type IS NULL OR LENGTH(TRIM(p_reason_type)) = 0 THEN
    RAISE EXCEPTION 'Credit transfer reason type is required';
  END IF;

  IF p_correlation_id IS NULL OR LENGTH(TRIM(p_correlation_id)) = 0 THEN
    RAISE EXCEPTION 'Credit transfer correlation ID is required';
  END IF;

  IF EXISTS (SELECT 1 FROM ledger_entries WHERE correlation_id = p_correlation_id) THEN
    RETURN QUERY
    SELECT
      'already_processed'::TEXT,
      l.id,
      l.amount,
      TRUE
    FROM ledger_entries l
    WHERE l.correlation_id = p_correlation_id
    LIMIT 1;
    RETURN;
  END IF;

  SELECT COUNT(*)
  INTO account_count
  FROM account_balances
  WHERE account_id IN (p_debit_account, p_credit_account)
  FOR UPDATE;

  IF account_count < 2 THEN
    RAISE EXCEPTION 'One or both accounts missing: debit=%, credit=%', p_debit_account, p_credit_account;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM account_balances
    WHERE account_id = p_debit_account
      AND balance >= p_amount
  ) THEN
    RAISE EXCEPTION 'Insufficient funds in debit account %', p_debit_account;
  END IF;

  UPDATE account_balances
  SET balance = balance - p_amount
  WHERE account_id = p_debit_account;

  UPDATE account_balances
  SET balance = balance + p_amount
  WHERE account_id = p_credit_account;

  INSERT INTO ledger_entries (
    id,
    game_day,
    debit_account,
    credit_account,
    amount,
    currency,
    reason_type,
    reason_id,
    rule_version,
    correlation_id
  ) VALUES (
    p_ledger_id,
    p_game_day,
    p_debit_account,
    p_credit_account,
    p_amount,
    'CREDIT',
    p_reason_type,
    p_reason_id,
    COALESCE(p_rule_version, 'v0.1'),
    p_correlation_id
  );

  RETURN QUERY
  SELECT
    'applied'::TEXT,
    p_ledger_id,
    p_amount,
    FALSE;
END;
$$;
