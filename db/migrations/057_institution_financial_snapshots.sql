-- EARTH ACTIVE MIGRATION: bounded daily institution financial projections

CREATE TABLE IF NOT EXISTS institution_financial_snapshots (
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  cash_treasury_units BIGINT NOT NULL CHECK (cash_treasury_units >= 0),
  cash_operations_units BIGINT NOT NULL CHECK (cash_operations_units >= 0),
  cash_reserve_units BIGINT NOT NULL CHECK (cash_reserve_units >= 0),
  period_revenue_units BIGINT NOT NULL CHECK (period_revenue_units >= 0),
  period_spending_units BIGINT NOT NULL CHECK (period_spending_units >= 0),
  budget_authorized_units BIGINT NOT NULL CHECK (budget_authorized_units >= 0),
  budget_committed_units BIGINT NOT NULL CHECK (budget_committed_units >= 0),
  budget_spent_units BIGINT NOT NULL CHECK (budget_spent_units >= 0),
  tax_receivable_units BIGINT NOT NULL CHECK (tax_receivable_units >= 0),
  arrears_units BIGINT NOT NULL CHECK (arrears_units >= 0),
  financial_state TEXT,
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, game_day),
  CHECK (budget_authorized_units >= budget_committed_units + budget_spent_units)
);

CREATE INDEX IF NOT EXISTS institution_financial_snapshots_day_idx
  ON institution_financial_snapshots (game_day, institution_id);
