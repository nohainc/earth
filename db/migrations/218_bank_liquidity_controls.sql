-- Finance V2 Plan 8: versioned lending and liquidity controls.

CREATE TABLE IF NOT EXISTS global_bank_rules (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version TEXT NOT NULL UNIQUE,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  minimum_liquidity_ratio NUMERIC(20,8) NOT NULL CHECK (minimum_liquidity_ratio >= 0),
  minimum_capital_ratio NUMERIC(20,8) NOT NULL CHECK (minimum_capital_ratio >= 0),
  maximum_single_borrower_exposure_units BIGINT NOT NULL CHECK (maximum_single_borrower_exposure_units > 0),
  maximum_total_lending_ratio NUMERIC(20,8) NOT NULL CHECK (maximum_total_lending_ratio >= 0),
  deposit_rate_bps INTEGER NOT NULL CHECK (deposit_rate_bps BETWEEN 0 AND 5000),
  loan_rate_bps INTEGER NOT NULL CHECK (loan_rate_bps BETWEEN 0 AND 5000),
  grace_period_days INTEGER NOT NULL CHECK (grace_period_days >= 0),
  default_threshold_days INTEGER NOT NULL CHECK (default_threshold_days >= grace_period_days),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS global_bank_rules_effective_range_uq
  ON global_bank_rules(effective_from_game_day, version);
INSERT INTO global_bank_rules (
  version, effective_from_game_day, minimum_liquidity_ratio, minimum_capital_ratio,
  maximum_single_borrower_exposure_units, maximum_total_lending_ratio,
  deposit_rate_bps, loan_rate_bps, grace_period_days, default_threshold_days
) VALUES ('global-bank-v2', 0, 0.20, 0.08, 100000000, 2.00, 10, 500, 2, 7)
ON CONFLICT (version) DO NOTHING;

CREATE OR REPLACE FUNCTION earth_validate_bank_loan_admission(
  p_borrower_economic_id BIGINT,
  p_principal_units BIGINT,
  p_game_day BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  rule global_bank_rules;
  reserve_units BIGINT;
  deposit_liabilities_units BIGINT;
  borrower_exposure_units BIGINT;
  total_lending_units BIGINT;
  projected_reserve_units BIGINT;
  projected_assets_units BIGINT;
  projected_equity_units BIGINT;
BEGIN
  SELECT * INTO rule FROM global_bank_rules
  WHERE effective_from_game_day <= p_game_day
    AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)
  ORDER BY effective_from_game_day DESC, id DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'No effective Global Bank rule exists for game day %', p_game_day; END IF;
  IF NOT EXISTS (SELECT 1 FROM owner_registry WHERE economic_id = p_borrower_economic_id AND owner_type IN ('human', 'city', 'corporation') AND status = 'active') THEN
    RAISE EXCEPTION 'Borrower is not eligible for a Global Bank loan';
  END IF;
  SELECT COALESCE(SUM(a.balance), 0) INTO reserve_units FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  WHERE o.id = 'SYSTEM-GLOBAL-BANK' AND a.asset_id = 1 AND a.account_type = 10 AND a.status = 'active';
  SELECT COALESCE(SUM(principal_units + accrued_interest_units), 0) INTO deposit_liabilities_units FROM bank_deposits WHERE status IN ('ACTIVE', 'MATURED');
  SELECT COALESCE(SUM(outstanding_principal_units + accrued_interest_units), 0) INTO borrower_exposure_units FROM bank_loans
  WHERE borrower_economic_id = p_borrower_economic_id AND status NOT IN ('REPAID', 'WRITTEN_OFF');
  IF borrower_exposure_units + p_principal_units > rule.maximum_single_borrower_exposure_units THEN RAISE EXCEPTION 'Loan exceeds maximum single-borrower exposure'; END IF;
  SELECT COALESCE(SUM(outstanding_principal_units), 0) INTO total_lending_units FROM bank_loans WHERE status NOT IN ('REPAID', 'WRITTEN_OFF');
  IF deposit_liabilities_units > 0 AND total_lending_units + p_principal_units > (deposit_liabilities_units * rule.maximum_total_lending_ratio) THEN RAISE EXCEPTION 'Loan exceeds maximum total lending ratio'; END IF;
  projected_reserve_units := reserve_units - p_principal_units;
  IF deposit_liabilities_units > 0 AND projected_reserve_units::NUMERIC / deposit_liabilities_units < rule.minimum_liquidity_ratio THEN RAISE EXCEPTION 'Loan would breach minimum liquidity ratio'; END IF;
  projected_assets_units := projected_reserve_units + total_lending_units + p_principal_units;
  projected_equity_units := projected_assets_units - deposit_liabilities_units;
  IF projected_assets_units > 0 AND projected_equity_units::NUMERIC / projected_assets_units < rule.minimum_capital_ratio THEN RAISE EXCEPTION 'Loan would breach minimum capital ratio'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_validate_bank_rate_snapshot(
  p_game_day BIGINT,
  p_rate_bps INTEGER,
  p_rate_rule_version TEXT,
  p_is_loan BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  rule global_bank_rules;
  expected_rate_bps INTEGER;
BEGIN
  SELECT * INTO rule FROM global_bank_rules
  WHERE effective_from_game_day <= p_game_day
    AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)
  ORDER BY effective_from_game_day DESC, id DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'No effective Global Bank rule exists for game day %', p_game_day; END IF;
  expected_rate_bps := CASE WHEN p_is_loan THEN rule.loan_rate_bps ELSE rule.deposit_rate_bps END;
  IF p_rate_rule_version IS DISTINCT FROM rule.version OR p_rate_bps IS DISTINCT FROM expected_rate_bps THEN
    RAISE EXCEPTION 'Bank rate snapshot does not match effective rule %', rule.version;
  END IF;
END;
$$;

-- Enforce admission inside the existing transaction, immediately before funds
-- are posted. This keeps the risk check and the V2 transfer in one transaction.
DO $$
DECLARE
  definition_text TEXT;
  old_guard TEXT := '  IF reserve_units - deposit_liabilities_units < p_principal_units THEN';
  new_guard TEXT := '  PERFORM earth_validate_bank_loan_admission(borrower.economic_id, p_principal_units, world.game_day);'
    || chr(10) || '  PERFORM earth_validate_bank_rate_snapshot(world.game_day, p_rate_bps, p_rate_rule_version, TRUE);'
    || chr(10) || '  IF reserve_units - deposit_liabilities_units < p_principal_units THEN';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_originate_v2_bank_loan' LIMIT 1;
  IF definition_text IS NULL OR position(old_guard IN definition_text) = 0 THEN RAISE EXCEPTION 'Cannot install bank loan admission control'; END IF;
  EXECUTE replace(definition_text, old_guard, new_guard);
END;
$$;

DO $$
DECLARE
  definition_text TEXT;
  old_call TEXT := '  SELECT game_day, game_minute INTO world FROM world_state WHERE id = ''WORLD'';';
  new_call TEXT := old_call || chr(10)
    || '  PERFORM earth_validate_bank_rate_snapshot(world.game_day, p_rate_bps, p_rate_rule_version, FALSE);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_create_v2_bank_deposit' LIMIT 1;
  IF definition_text IS NULL OR position(old_call IN definition_text) = 0 THEN RAISE EXCEPTION 'Cannot install bank deposit rate control'; END IF;
  EXECUTE replace(definition_text, old_call, new_call);
END;
$$;
