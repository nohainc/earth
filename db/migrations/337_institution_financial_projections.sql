-- Cities, Corporations & Budgets V2 Plan 31.
-- Fast institutional financial read models. Economy V2 accounts and contracts
-- remain authoritative; this table is a rebuildable projection only.

ALTER TABLE institution_financial_summary
  ADD COLUMN IF NOT EXISTS period_revenue_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS period_spending_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS budget_authorized_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS budget_committed_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS budget_spent_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS arrears_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mandatory_commitments_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS surplus_deficit_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS liquidity_days NUMERIC(20,4),
  ADD COLUMN IF NOT EXISTS research_commitments_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS city_support_commitments_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dividend_capacity_units BIGINT NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION earth_refresh_daily_financial_projections(p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  -- Owner projections remain the source for personal finance screens.
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

  INSERT INTO institution_financial_summary (
    institution_id, institution_kind, game_day, treasury_units, operations_units, reserve_units,
    committed_spending_units, debt_units, tax_receivables_units, distributable_surplus_units,
    period_revenue_units, period_spending_units, budget_authorized_units, budget_committed_units,
    budget_spent_units, arrears_units, mandatory_commitments_units, surplus_deficit_units,
    liquidity_days, research_commitments_units, city_support_commitments_units, dividend_capacity_units,
    updated_at
  )
  SELECT i.id, i.kind, p_game_day,
    cash.treasury_units, cash.operations_units, cash.reserve_units,
    budgets.budget_committed_units, obligations.debt_units, obligations.tax_receivables_units,
    CASE WHEN i.kind = 'CORPORATION' THEN earth_corporation_distributable_surplus(i.id, p_game_day) ELSE 0 END,
    revenue.period_revenue_units, budgets.period_spending_units, budgets.budget_authorized_units,
    budgets.budget_committed_units, budgets.budget_spent_units, obligations.arrears_units,
    commitments.mandatory_commitments_units,
    revenue.period_revenue_units - budgets.period_spending_units,
    CASE WHEN commitments.mandatory_commitments_units > 0
      THEN ROUND((cash.treasury_units + cash.operations_units + cash.reserve_units)::NUMERIC /
        (commitments.mandatory_commitments_units::NUMERIC / GREATEST(1, COALESCE(period.end_game_day - p_game_day + 1, 1))), 4)
      ELSE NULL END,
    commitments.research_commitments_units, commitments.city_support_commitments_units,
    CASE WHEN i.kind = 'CORPORATION' THEN earth_corporation_distributable_surplus(i.id, p_game_day) ELSE 0 END,
    CURRENT_TIMESTAMP
  FROM institutions i
  JOIN owner_registry o ON o.id = i.id AND o.status = 'active'
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 3), 0) AS treasury_units,
      COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 4), 0) AS operations_units,
      COALESCE(SUM(a.balance) FILTER (WHERE a.asset_id = 1 AND a.account_type = 5), 0) AS reserve_units
    FROM economic_accounts a
    WHERE a.owner_economic_id = o.economic_id AND a.status = 'active'
  ) cash ON TRUE
  LEFT JOIN LATERAL (
    SELECT fp.id, fp.end_game_day
    FROM fiscal_periods fp
    WHERE p_game_day BETWEEN fp.start_game_day AND fp.end_game_day
    ORDER BY fp.start_game_day DESC LIMIT 1
  ) period ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(r.taxes_received + r.service_revenue + r.grants_received + r.license_income + r.other_income), 0) AS period_revenue_units,
      COALESCE((SELECT SUM(l.spent_units) FROM institution_budget_lines l WHERE l.institution_id = i.id AND l.fiscal_period_id = period.id), 0) AS period_spending_units
    FROM institution_revenue_summary r
    WHERE r.institution_id = i.id AND r.fiscal_period_id = period.id
  ) revenue ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(l.authorized_units), 0) AS budget_authorized_units,
      COALESCE(SUM(l.committed_units), 0) AS budget_committed_units,
      COALESCE(SUM(l.spent_units), 0) AS budget_spent_units,
      COALESCE(SUM(l.spent_units), 0) AS period_spending_units
    FROM institution_budget_lines l
    WHERE l.institution_id = i.id AND l.fiscal_period_id = period.id
  ) budgets ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(c.remaining_units) FILTER (WHERE bc.mandatory), 0) AS mandatory_commitments_units,
      COALESCE(SUM(c.remaining_units) FILTER (WHERE bc.category_code = 'RESEARCH'), 0) AS research_commitments_units,
      COALESCE(SUM(c.remaining_units) FILTER (WHERE bc.category_code = 'CITY_SUPPORT'), 0) AS city_support_commitments_units
    FROM institution_budget_commitments c
    JOIN institution_budget_lines l ON l.id = c.budget_line_id
    JOIN budget_categories bc ON bc.id = l.category_id
    WHERE c.institution_id = i.id AND c.status IN ('ACTIVE', 'PARTIALLY_PAID')
  ) commitments ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      COALESCE((SELECT SUM(l.outstanding_principal_units + l.accrued_interest_units) FROM bank_loans l WHERE l.borrower_economic_id = o.economic_id AND l.status NOT IN ('REPAID','WRITTEN_OFF')), 0) AS debt_units,
      COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.beneficiary_economic_id = o.economic_id AND t.status IN ('DUE','PARTIAL','ARREARS')), 0) AS tax_receivables_units,
      COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.taxpayer_economic_id = o.economic_id AND t.status IN ('ARREARS','PARTIAL')), 0) AS arrears_units
  ) obligations ON TRUE
  WHERE i.status = 'active'
  ON CONFLICT (institution_id) DO UPDATE SET
    institution_kind = EXCLUDED.institution_kind, game_day = EXCLUDED.game_day,
    treasury_units = EXCLUDED.treasury_units, operations_units = EXCLUDED.operations_units,
    reserve_units = EXCLUDED.reserve_units, committed_spending_units = EXCLUDED.committed_spending_units,
    debt_units = EXCLUDED.debt_units, tax_receivables_units = EXCLUDED.tax_receivables_units,
    distributable_surplus_units = EXCLUDED.distributable_surplus_units,
    period_revenue_units = EXCLUDED.period_revenue_units, period_spending_units = EXCLUDED.period_spending_units,
    budget_authorized_units = EXCLUDED.budget_authorized_units, budget_committed_units = EXCLUDED.budget_committed_units,
    budget_spent_units = EXCLUDED.budget_spent_units, arrears_units = EXCLUDED.arrears_units,
    mandatory_commitments_units = EXCLUDED.mandatory_commitments_units, surplus_deficit_units = EXCLUDED.surplus_deficit_units,
    liquidity_days = EXCLUDED.liquidity_days, research_commitments_units = EXCLUDED.research_commitments_units,
    city_support_commitments_units = EXCLUDED.city_support_commitments_units, dividend_capacity_units = EXCLUDED.dividend_capacity_units,
    updated_at = CURRENT_TIMESTAMP;

  INSERT INTO tax_daily_summary
  SELECT p_game_day, COALESCE(SUM(amount_units),0), COALESCE(SUM(amount_units) FILTER (WHERE status = 'PAID'),0), COALESCE(SUM(amount_units) FILTER (WHERE status IN ('ARREARS','DUE','PARTIAL')),0), COALESCE(SUM(amount_units) FILTER (WHERE status = 'WAIVED'),0), COUNT(*)
    FROM tax_obligations WHERE game_day = p_game_day
  ON CONFLICT (game_day) DO UPDATE SET assessed_units = EXCLUDED.assessed_units, paid_units = EXCLUDED.paid_units, arrears_units = EXCLUDED.arrears_units, waived_units = EXCLUDED.waived_units, obligation_count = EXCLUDED.obligation_count, updated_at = CURRENT_TIMESTAMP;
END;
$$;

CREATE OR REPLACE VIEW institution_financial_projections AS
SELECT s.institution_id, s.institution_kind, s.game_day,
  s.treasury_units AS cash_treasury_units,
  s.operations_units AS cash_operations_units,
  s.reserve_units AS cash_reserve_units,
  s.period_revenue_units, s.period_spending_units,
  s.budget_authorized_units, s.budget_committed_units, s.budget_spent_units,
  s.tax_receivables_units AS tax_receivable_units, s.arrears_units,
  s.mandatory_commitments_units, s.surplus_deficit_units, s.liquidity_days,
  COALESCE(fs.status, 'active') AS financial_state,
  s.distributable_surplus_units, s.research_commitments_units,
  s.city_support_commitments_units, s.dividend_capacity_units, s.updated_at
FROM institution_financial_summary s
LEFT JOIN financial_states fs ON fs.institution_id = s.institution_id;

CREATE INDEX IF NOT EXISTS institution_financial_summary_game_day_idx
  ON institution_financial_summary(game_day, institution_kind);

-- Kept separate so a fresh-install schema can use the same projection refresh
-- even while older owner/tax projection logic is retained in the baseline.
CREATE OR REPLACE FUNCTION earth_refresh_institution_financial_projection_fields(p_game_day BIGINT)
RETURNS VOID LANGUAGE SQL AS $$
WITH periods AS (
  SELECT id, start_game_day, end_game_day
  FROM fiscal_periods
  WHERE p_game_day BETWEEN start_game_day AND end_game_day
  ORDER BY start_game_day DESC
  LIMIT 1
), metrics AS (
  SELECT i.id AS institution_id,
    COALESCE((SELECT SUM(r.taxes_received + r.service_revenue + r.grants_received + r.license_income + r.other_income) FROM institution_revenue_summary r, periods p WHERE r.institution_id = i.id AND r.fiscal_period_id = p.id), 0) AS revenue,
    COALESCE((SELECT SUM(l.spent_units) FROM institution_budget_lines l, periods p WHERE l.institution_id = i.id AND l.fiscal_period_id = p.id), 0) AS spending,
    COALESCE((SELECT SUM(l.authorized_units) FROM institution_budget_lines l, periods p WHERE l.institution_id = i.id AND l.fiscal_period_id = p.id), 0) AS authorized,
    COALESCE((SELECT SUM(l.committed_units) FROM institution_budget_lines l, periods p WHERE l.institution_id = i.id AND l.fiscal_period_id = p.id), 0) AS committed,
    COALESCE((SELECT SUM(l.spent_units) FROM institution_budget_lines l, periods p WHERE l.institution_id = i.id AND l.fiscal_period_id = p.id), 0) AS spent,
    COALESCE((SELECT SUM(c.remaining_units) FROM institution_budget_commitments c JOIN institution_budget_lines l ON l.id = c.budget_line_id JOIN budget_categories bc ON bc.id = l.category_id WHERE c.institution_id = i.id AND c.status IN ('ACTIVE','PARTIALLY_PAID') AND bc.mandatory), 0) AS mandatory,
    COALESCE((SELECT SUM(c.remaining_units) FROM institution_budget_commitments c JOIN institution_budget_lines l ON l.id = c.budget_line_id JOIN budget_categories bc ON bc.id = l.category_id WHERE c.institution_id = i.id AND c.status IN ('ACTIVE','PARTIALLY_PAID') AND bc.category_code = 'RESEARCH'), 0) AS research,
    COALESCE((SELECT SUM(c.remaining_units) FROM institution_budget_commitments c JOIN institution_budget_lines l ON l.id = c.budget_line_id JOIN budget_categories bc ON bc.id = l.category_id WHERE c.institution_id = i.id AND c.status IN ('ACTIVE','PARTIALLY_PAID') AND bc.category_code = 'CITY_SUPPORT'), 0) AS city_support,
    COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.taxpayer_economic_id = o.economic_id AND t.status IN ('ARREARS','PARTIAL')), 0) AS arrears,
    COALESCE((SELECT SUM(t.amount_units) FROM tax_obligations t WHERE t.beneficiary_economic_id = o.economic_id AND t.status IN ('DUE','PARTIAL','ARREARS')), 0) AS receivables,
    COALESCE((SELECT SUM(a.balance) FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.status = 'active'), 0) AS treasury,
    COALESCE((SELECT SUM(a.balance) FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 4 AND a.status = 'active'), 0) AS operations,
    COALESCE((SELECT SUM(a.balance) FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 5 AND a.status = 'active'), 0) AS reserve,
    COALESCE((SELECT end_game_day FROM periods), p_game_day) AS period_end
  FROM institutions i JOIN owner_registry o ON o.id = i.id
)
UPDATE institution_financial_summary s
SET game_day = p_game_day,
    treasury_units = m.treasury, operations_units = m.operations, reserve_units = m.reserve,
    period_revenue_units = m.revenue, period_spending_units = m.spending,
    budget_authorized_units = m.authorized, budget_committed_units = m.committed, budget_spent_units = m.spent,
    arrears_units = m.arrears, mandatory_commitments_units = m.mandatory,
    surplus_deficit_units = m.revenue - m.spending,
    liquidity_days = CASE WHEN m.mandatory > 0 THEN ROUND((m.treasury + m.operations + m.reserve)::NUMERIC / (m.mandatory::NUMERIC / GREATEST(1, m.period_end - p_game_day + 1)), 4) ELSE NULL END,
    research_commitments_units = m.research, city_support_commitments_units = m.city_support,
    dividend_capacity_units = CASE WHEN s.institution_kind = 'CORPORATION' THEN earth_corporation_distributable_surplus(s.institution_id, p_game_day) ELSE 0 END,
    updated_at = CURRENT_TIMESTAMP
FROM metrics m
WHERE s.institution_id = m.institution_id;
$$;
