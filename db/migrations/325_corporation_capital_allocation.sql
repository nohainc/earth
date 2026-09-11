-- Cities, Corporations & Budgets V2 Plan 13.
-- Corporation dividend capacity is a derived eligibility value, not a balance.

INSERT INTO budget_categories (institution_kind, category_code, mandatory, priority, rules)
VALUES ('CORPORATION', 'RESERVE', TRUE, 10, '{"minimum_reserve_bps":1000}'::JSONB)
ON CONFLICT (institution_kind, category_code) DO UPDATE
SET mandatory = EXCLUDED.mandatory, priority = EXCLUDED.priority, rules = EXCLUDED.rules;

CREATE OR REPLACE FUNCTION earth_corporation_distributable_surplus(
  p_institution_id TEXT,
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_owner_economic_id BIGINT;
  cash_units BIGINT;
  required_reserve_units BIGINT;
  mandatory_commitments BIGINT;
  tax_due BIGINT;
  loan_due BIGINT;
BEGIN
  SELECT economic_id INTO v_owner_economic_id
    FROM owner_registry
   WHERE id = p_institution_id AND owner_type = 'corporation' AND status = 'active';
  IF v_owner_economic_id IS NULL THEN RETURN 0; END IF;

  SELECT COALESCE(balance, 0) INTO cash_units
    FROM economic_accounts
   WHERE economic_accounts.owner_economic_id = v_owner_economic_id AND asset_id = 1 AND account_type = 3
     AND is_default_settlement AND status = 'active';
  required_reserve_units := (cash_units * 1000) / 10000;

  SELECT COALESCE(SUM(c.remaining_units), 0) INTO mandatory_commitments
    FROM institution_budget_commitments c
    JOIN institution_budget_lines l ON l.id = c.budget_line_id
    JOIN budget_categories bc ON bc.id = l.category_id
   WHERE l.institution_id = p_institution_id
     AND c.status IN ('ACTIVE', 'PARTIALLY_PAID')
     AND bc.mandatory
     AND c.due_game_day <= p_game_day;
  SELECT COALESCE(SUM(amount_units), 0) INTO tax_due
    FROM tax_obligations
   WHERE taxpayer_economic_id = v_owner_economic_id AND status IN ('DUE', 'PARTIAL', 'ARREARS');
  SELECT COALESCE(SUM(LEAST(outstanding_principal_units + accrued_interest_units,
      accrued_interest_units + CASE WHEN remaining_installments > 0 THEN (outstanding_principal_units + remaining_installments - 1) / remaining_installments ELSE 0 END)), 0)
    INTO loan_due
    FROM bank_loans
   WHERE borrower_economic_id = v_owner_economic_id
     AND status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'RESTRUCTURED')
     AND next_payment_game_day <= p_game_day;
  RETURN GREATEST(0, cash_units - mandatory_commitments - tax_due - loan_due - required_reserve_units);
END;
$$;

COMMENT ON FUNCTION earth_corporation_distributable_surplus(TEXT, BIGINT) IS
  'Derived dividend capacity after mandatory commitments, taxes, debt service, and required reserve; not an economic account.';
