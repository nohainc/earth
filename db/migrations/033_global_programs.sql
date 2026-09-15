-- EARTH ACTIVE MIGRATION: constitutional global programs and bounded progress

CREATE TABLE IF NOT EXISTS global_programs (
  id TEXT PRIMARY KEY,
  program_type TEXT NOT NULL CHECK (program_type IN ('TECHNOLOGY','COMMONS','EMERGENCY')),
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','ACTIVE','COMPLETED','CANCELLED')),
  authorized_units BIGINT NOT NULL DEFAULT 0 CHECK (authorized_units >= 0),
  funded_units BIGINT NOT NULL DEFAULT 0 CHECK (funded_units >= 0 AND funded_units <= authorized_units),
  spent_units BIGINT NOT NULL DEFAULT 0 CHECK (spent_units >= 0 AND spent_units <= funded_units),
  progress_units BIGINT NOT NULL DEFAULT 0 CHECK (progress_units >= 0),
  target_units BIGINT NOT NULL CHECK (target_units > 0),
  recipient_account_id BIGINT REFERENCES economic_accounts(id),
  authorization_proposal_id TEXT REFERENCES governance_proposals_v4(id),
  created_game_day BIGINT NOT NULL,
  completed_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK (status <> 'ACTIVE' OR authorization_proposal_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS global_programs_status_idx ON global_programs (status, created_game_day DESC);
CREATE TABLE IF NOT EXISTS global_program_progress (
  id BIGSERIAL PRIMARY KEY,
  program_id TEXT NOT NULL REFERENCES global_programs(id),
  game_day BIGINT NOT NULL,
  progress_units BIGINT NOT NULL CHECK (progress_units > 0),
  funding_spent_units BIGINT NOT NULL CHECK (funding_spent_units >= 0),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS global_program_progress_program_day_idx ON global_program_progress (program_id, game_day DESC);
