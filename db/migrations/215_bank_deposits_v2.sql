-- Finance V2 Plan 5: deposits are liabilities backed by bank-reserve CREDIT.

CREATE TABLE IF NOT EXISTS bank_deposits (
  id TEXT PRIMARY KEY,
  depositor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  principal_units BIGINT NOT NULL CHECK (principal_units > 0),
  accrued_interest_units BIGINT NOT NULL DEFAULT 0 CHECK (accrued_interest_units >= 0),
  rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0 AND rate_bps <= 5000),
  rate_rule_version TEXT NOT NULL,
  start_total_game_minute BIGINT NOT NULL CHECK (start_total_game_minute >= 0),
  maturity_total_game_minute BIGINT NOT NULL CHECK (maturity_total_game_minute > start_total_game_minute),
  early_withdrawal_allowed BOOLEAN NOT NULL DEFAULT FALSE,
  early_withdrawal_penalty_bps INTEGER NOT NULL DEFAULT 0 CHECK (early_withdrawal_penalty_bps BETWEEN 0 AND 10000),
  rules_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'MATURED', 'WITHDRAWN', 'ROLLED_OVER', 'DEFAULTED')),
  created_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  payout_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS bank_deposits_owner_status_idx ON bank_deposits(depositor_economic_id, status, maturity_total_game_minute);
CREATE INDEX IF NOT EXISTS bank_deposits_maturity_idx ON bank_deposits(status, maturity_total_game_minute);

CREATE OR REPLACE FUNCTION earth_create_v2_bank_deposit(
  p_deposit_id TEXT,
  p_human_id TEXT,
  p_principal_units BIGINT,
  p_term_days INTEGER,
  p_correlation_id TEXT,
  p_rate_bps INTEGER DEFAULT 10,
  p_rate_rule_version TEXT DEFAULT 'global-bank-v2'
)
RETURNS bank_deposits
LANGUAGE plpgsql
AS $$
DECLARE
  deposit bank_deposits;
  transaction_row RECORD;
  world RECORD;
  depositor_account BIGINT;
  bank_account BIGINT;
  depositor_economic_id BIGINT;
  start_minute BIGINT;
BEGIN
  SELECT * INTO deposit FROM bank_deposits WHERE correlation_id = p_correlation_id OR id = p_deposit_id;
  IF FOUND THEN RETURN deposit; END IF;
  IF p_principal_units IS NULL OR p_principal_units <= 0 THEN RAISE EXCEPTION 'Deposit principal must be positive'; END IF;
  IF p_term_days IS NULL OR p_term_days < 1 OR p_term_days > 90 THEN RAISE EXCEPTION 'Deposit term must be between 1 and 90 game days'; END IF;
  IF p_correlation_id IS NULL OR length(btrim(p_correlation_id)) = 0 THEN RAISE EXCEPTION 'Deposit correlation ID is required'; END IF;

  depositor_economic_id := earth_private_economic_owner_id(p_human_id);
  SELECT a.id INTO depositor_account FROM economic_accounts a WHERE a.owner_economic_id = depositor_economic_id AND a.asset_id = 1 AND a.account_type = 1 AND a.is_default_settlement AND a.status = 'active';
  SELECT a.id INTO bank_account FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active';
  IF depositor_account IS NULL OR bank_account IS NULL THEN RAISE EXCEPTION 'V2 depositor or bank reserve account is unavailable'; END IF;
  SELECT game_day, game_minute INTO world FROM world_state WHERE id = 'WORLD';
  start_minute := (world.game_day - 1) * 1440 + world.game_minute;

  SELECT * INTO transaction_row FROM earth_post_transaction(
    p_correlation_id, world.game_day, world.game_minute, 'bank_deposit', 'global_bank', p_deposit_id, p_rate_rule_version,
    jsonb_build_array(
      jsonb_build_object('account_id', depositor_account, 'delta', -p_principal_units, 'reason_code', 'BANK_DEPOSIT_FUNDING'),
      jsonb_build_object('account_id', bank_account, 'delta', p_principal_units, 'reason_code', 'BANK_DEPOSIT_FUNDING')
    )
  );

  INSERT INTO bank_deposits (
    id, depositor_economic_id, principal_units, rate_bps, rate_rule_version,
    start_total_game_minute, maturity_total_game_minute, early_withdrawal_allowed,
    early_withdrawal_penalty_bps, rules_snapshot, created_transaction_id, correlation_id
  ) VALUES (
    p_deposit_id, depositor_economic_id, p_principal_units, p_rate_bps, p_rate_rule_version,
    start_minute, start_minute + p_term_days * 1440, FALSE, 0,
    jsonb_build_object('rateBps', p_rate_bps, 'rateRuleVersion', p_rate_rule_version, 'earlyWithdrawalAllowed', FALSE, 'earlyWithdrawalPenaltyBps', 0),
    transaction_row.transaction_id, p_correlation_id
  ) RETURNING * INTO deposit;
  RETURN deposit;
END;
$$;
