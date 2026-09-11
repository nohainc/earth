-- Cities, Corporations & Budgets V2 Plan 10.
-- Restricted grants constrain recipient budget authority without creating wallets.

CREATE TABLE grant_restrictions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grant_id BIGINT NOT NULL REFERENCES institution_grants(id),
  recipient_institution_id TEXT NOT NULL REFERENCES institutions(id),
  budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  category_id BIGINT NOT NULL REFERENCES budget_categories(id),
  original_units BIGINT NOT NULL CHECK (original_units > 0),
  remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0 AND remaining_units <= original_units),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXHAUSTED', 'CANCELLED')),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (grant_id, budget_line_id),
  CHECK (recipient_institution_id <> '')
);

CREATE INDEX grant_restrictions_spending_idx ON grant_restrictions (recipient_institution_id, budget_line_id, status);
