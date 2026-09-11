-- Cities, Corporations & Budgets V2 Plan 9.
-- Grants are transfers, not recipient spending.

CREATE TABLE institution_grants (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grantor_institution_id TEXT NOT NULL REFERENCES institutions(id),
  recipient_institution_id TEXT NOT NULL REFERENCES institutions(id),
  budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines(id),
  commitment_id BIGINT REFERENCES institution_budget_commitments(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  grant_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'APPROVED' CHECK (status IN ('APPROVED', 'PAID', 'CANCELLED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  paid_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (grantor_institution_id <> recipient_institution_id)
);

CREATE INDEX institution_grants_status_idx
  ON institution_grants (status, grantor_institution_id, recipient_institution_id);
