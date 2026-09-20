-- EARTH ACTIVE MIGRATION: one financial/execution lifecycle for all Initiatives.

CREATE TABLE IF NOT EXISTS initiative_contributions (
  id TEXT PRIMARY KEY,
  initiative_id TEXT NOT NULL REFERENCES v5_initiatives(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  matching_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_units >= 0),
  escrow_account_id BIGINT REFERENCES economic_accounts(id),
  contribution_transaction_id BIGINT REFERENCES economic_transactions(id),
  status TEXT NOT NULL DEFAULT 'ESCROWED' CHECK (status IN ('ESCROWED','APPLIED','RELEASED','REFUNDED','CANCELLED')),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  settled_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS initiative_contributions_initiative_idx ON initiative_contributions(initiative_id, status, created_game_day);
CREATE INDEX IF NOT EXISTS initiative_contributions_house_idx ON initiative_contributions(house_id, initiative_id, created_game_day DESC);

CREATE TABLE IF NOT EXISTS initiative_funding_commitments (
  id TEXT PRIMARY KEY,
  initiative_id TEXT NOT NULL REFERENCES v5_initiatives(id),
  source_type TEXT NOT NULL CHECK (source_type IN ('EARTH','CORPORATION')),
  source_id TEXT,
  authorized_units BIGINT NOT NULL CHECK (authorized_units >= 0),
  committed_units BIGINT NOT NULL DEFAULT 0 CHECK (committed_units >= 0 AND committed_units <= authorized_units),
  status TEXT NOT NULL DEFAULT 'AUTHORIZED' CHECK (status IN ('AUTHORIZED','COMMITTED','RELEASED','CANCELLED')),
  governance_proposal_id TEXT NOT NULL REFERENCES v5_governance_proposals(id),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK ((source_type = 'EARTH' AND source_id IS NULL) OR (source_type = 'CORPORATION' AND source_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS initiative_funding_commitments_scope_uq ON initiative_funding_commitments(initiative_id, source_type, source_id);

CREATE TABLE IF NOT EXISTS initiative_executions (
  id TEXT PRIMARY KEY,
  initiative_id TEXT NOT NULL UNIQUE REFERENCES v5_initiatives(id),
  execution_model TEXT NOT NULL CHECK (execution_model IN ('FUNDING_ONLY','TIMED_PROGRAM','PUBLIC_WORK')),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACTIVE','COMPLETED','FAILED','CANCELLED')),
  progress_bps INTEGER NOT NULL DEFAULT 0 CHECK (progress_bps BETWEEN 0 AND 10000),
  started_game_day BIGINT,
  completed_game_day BIGINT,
  execution_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS initiative_outcomes (
  id TEXT PRIMARY KEY,
  initiative_id TEXT NOT NULL REFERENCES v5_initiatives(id),
  outcome_type TEXT NOT NULL,
  outcome JSONB NOT NULL CHECK (jsonb_typeof(outcome) = 'object'),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPLIED','FAILED','REVOKED')),
  effective_game_day BIGINT,
  applied_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS initiative_outcomes_initiative_idx ON initiative_outcomes(initiative_id, status, effective_game_day);

-- Legacy rows are deliberately not copied into a second ledger. Local/test
-- environments can discard the obsolete engines after this migration; any
-- future materialization must originate from v5_initiatives and V5 Governance.
