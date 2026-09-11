-- Cities, Corporations & Budgets V2 Plan 2.
-- The old percentage/decimal budget table is retired. Budget lines are
-- permissions to spend; institutional CREDIT remains in Economy V2 accounts.

ALTER TABLE IF EXISTS institution_budgets
  RENAME TO institution_budget_lines;

ALTER INDEX IF EXISTS institution_budgets_period_idx
  RENAME TO institution_budget_lines_period_idx;

-- Preserve any legacy budget authorizations that were not already represented
-- in the V2 table. Decimal Credits become integer CREDIT minor units. Use
-- dynamic SQL so the migration is also safe for databases initialized from
-- the already-clean canonical schema, where the legacy table never existed.
DO $$
BEGIN
  IF to_regclass('public.budgets') IS NOT NULL THEN
    EXECUTE $sql$
      INSERT INTO institution_budget_lines (
        institution_id, game_period, category, authorized_units,
        committed_units, spent_units, rule_version
      )
      SELECT b.institution_id, b.game_day, b.category,
             ROUND(b.amount * 100)::BIGINT, 0, 0, 'legacy-budget-v1'
      FROM budgets b
      ON CONFLICT (institution_id, game_period, category) DO NOTHING
    $sql$;
    DROP TABLE budgets;
  END IF;
END;
$$;

COMMENT ON TABLE institution_budget_lines IS
  'Budget authorization lines only; institutional CREDIT remains exclusively in Economy V2 accounts.';

-- Rebind the financial projection function created before the table rename.
-- PL/pgSQL resolves relation names when the function runs, so redefine it
-- rather than leaving a runtime dependency on the retired table name.
CREATE OR REPLACE FUNCTION earth_refresh_daily_financial_projections(p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO owner_financial_summary
  SELECT o.economic_id, p_game_day,
    COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type NOT IN (6,7,8)), 0),
    COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 6), 0),
    COALESCE((SELECT SUM(d.principal_units) FROM bank_deposits d WHERE d.depositor_economic_id = o.economic_id AND d.status IN ('ACTIVE','MATURED')), 0),
    COALESCE((SELECT SUM(d.accrued_interest_units) FROM bank_deposits d WHERE d.depositor_economic_id = o.economic_id AND d.status IN ('ACTIVE','MATURED')), 0),
    COALESCE((SELECT SUM(l.outstanding_principal_units + l.accrued_interest_units) FROM bank_loans l WHERE l.borrower_economic_id = o.economic_id AND l.status NOT IN ('REPAID','WRITTEN_OFF')), 0),
    COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.taxpayer_economic_id = o.economic_id AND t.status IN ('ARREARS','DUE','PARTIAL')), 0),
    COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type NOT IN (7,8)), 0)
      + COALESCE((SELECT SUM(d.principal_units + d.accrued_interest_units) FROM bank_deposits d WHERE d.depositor_economic_id = o.economic_id AND d.status IN ('ACTIVE','MATURED')), 0)
      - COALESCE((SELECT SUM(l.outstanding_principal_units + l.accrued_interest_units) FROM bank_loans l WHERE l.borrower_economic_id = o.economic_id AND l.status NOT IN ('REPAID','WRITTEN_OFF')), 0)
      - COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.taxpayer_economic_id = o.economic_id AND t.status IN ('ARREARS','DUE','PARTIAL')), 0),
    CURRENT_TIMESTAMP
  FROM owner_registry o LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.status = 'active'
  WHERE o.status = 'active' GROUP BY o.economic_id
  ON CONFLICT (owner_economic_id) DO UPDATE SET game_day = EXCLUDED.game_day, liquid_credit_units = EXCLUDED.liquid_credit_units, escrowed_credit_units = EXCLUDED.escrowed_credit_units, deposit_principal_units = EXCLUDED.deposit_principal_units, deposit_interest_units = EXCLUDED.deposit_interest_units, loan_liabilities_units = EXCLUDED.loan_liabilities_units, tax_arrears_units = EXCLUDED.tax_arrears_units, net_financial_position_units = EXCLUDED.net_financial_position_units, updated_at = CURRENT_TIMESTAMP;

  INSERT INTO institution_financial_summary
  SELECT i.id, i.kind, p_game_day,
    COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 3), 0),
    COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 4), 0),
    COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 5), 0),
    COALESCE((SELECT SUM(GREATEST(0, b.committed_units - b.spent_units)) FROM institution_budget_lines b WHERE b.institution_id = i.id), 0),
    COALESCE((SELECT SUM(l.outstanding_principal_units + l.accrued_interest_units) FROM bank_loans l WHERE l.borrower_economic_id = o.economic_id AND l.status NOT IN ('REPAID','WRITTEN_OFF')), 0),
    COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.beneficiary_economic_id = o.economic_id AND t.status IN ('DUE','PARTIAL','ARREARS')), 0),
    GREATEST(0, COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 3), 0) - COALESCE((SELECT SUM(GREATEST(0, b.committed_units - b.spent_units)) FROM institution_budget_lines b WHERE b.institution_id = i.id), 0)),
    CURRENT_TIMESTAMP
  FROM institutions i JOIN owner_registry o ON o.id = i.id LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.status = 'active'
  WHERE i.status = 'active' GROUP BY i.id, i.kind, o.economic_id
  ON CONFLICT (institution_id) DO UPDATE SET game_day = EXCLUDED.game_day, treasury_units = EXCLUDED.treasury_units, operations_units = EXCLUDED.operations_units, reserve_units = EXCLUDED.reserve_units, committed_spending_units = EXCLUDED.committed_spending_units, debt_units = EXCLUDED.debt_units, tax_receivables_units = EXCLUDED.tax_receivables_units, distributable_surplus_units = EXCLUDED.distributable_surplus_units, updated_at = CURRENT_TIMESTAMP;

  INSERT INTO tax_daily_summary
  SELECT p_game_day, COALESCE(SUM(amount_units),0), COALESCE(SUM(amount_units) FILTER (WHERE status = 'PAID'),0), COALESCE(SUM(amount_units) FILTER (WHERE status IN ('ARREARS','DUE','PARTIAL')),0), COALESCE(SUM(amount_units) FILTER (WHERE status = 'WAIVED'),0), COUNT(*)
    FROM tax_obligations WHERE game_day = p_game_day
  ON CONFLICT (game_day) DO UPDATE SET assessed_units = EXCLUDED.assessed_units, paid_units = EXCLUDED.paid_units, arrears_units = EXCLUDED.arrears_units, waived_units = EXCLUDED.waived_units, obligation_count = EXCLUDED.obligation_count, updated_at = CURRENT_TIMESTAMP;
END;
$$;
