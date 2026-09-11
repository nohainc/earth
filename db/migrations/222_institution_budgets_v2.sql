-- Finance V2 Plan 12: budgets authorize spending without holding money.

CREATE TABLE IF NOT EXISTS institution_budgets (
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  game_period BIGINT NOT NULL CHECK (game_period >= 0),
  category TEXT NOT NULL,
  authorized_units BIGINT NOT NULL CHECK (authorized_units >= 0),
  committed_units BIGINT NOT NULL DEFAULT 0 CHECK (committed_units >= 0),
  spent_units BIGINT NOT NULL DEFAULT 0 CHECK (spent_units >= 0),
  rule_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, game_period, category),
  CHECK (authorized_units >= committed_units),
  CHECK (committed_units >= spent_units)
);
CREATE INDEX IF NOT EXISTS institution_budgets_period_idx
  ON institution_budgets(game_period, institution_id, category);

COMMENT ON TABLE institution_budgets IS 'Spending authorization only; CREDIT remains exclusively in Economy V2 accounts.';
