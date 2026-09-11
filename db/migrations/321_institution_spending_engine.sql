-- Cities, Corporations & Budgets V2 Plan 7.
-- One audit record for every institutional budget-funded payment.

CREATE TABLE institution_spending_journals (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  commitment_id BIGINT REFERENCES institution_budget_commitments(id),
  source_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  recipient_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  purpose TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  economic_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX institution_spending_journals_institution_idx
  ON institution_spending_journals (institution_id, game_day DESC);
