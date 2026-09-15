-- EARTH ACTIVE MIGRATION: reusable V4 governance proposal and execution journal

CREATE TABLE IF NOT EXISTS governance_proposals_v4 (
  id TEXT PRIMARY KEY,
  subject_type TEXT NOT NULL CHECK (subject_type IN ('EARTH', 'ORGANIZATION')),
  subject_id TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  action_type TEXT NOT NULL CHECK (action_type IN ('ORGANIZATION_BUDGET_SPEND', 'TAX_RULE', 'PUBLIC_PROJECT', 'RESEARCH_FUNDING', 'CHARTER_CHANGE')),
  action_snapshot JSONB NOT NULL CHECK (jsonb_typeof(action_snapshot) = 'object'),
  rule_snapshot JSONB NOT NULL CHECK (jsonb_typeof(rule_snapshot) = 'object'),
  schema_version INTEGER NOT NULL DEFAULT 1 CHECK (schema_version > 0),
  electorate_method TEXT NOT NULL DEFAULT 'HOUSE_ONE_VOTE',
  voting_method TEXT NOT NULL DEFAULT 'SIMPLE_MAJORITY',
  status TEXT NOT NULL DEFAULT 'VOTING' CHECK (status IN ('VOTING', 'PASSED', 'REJECTED', 'EXECUTED', 'FAILED', 'CANCELLED')),
  submitted_game_day BIGINT NOT NULL CHECK (submitted_game_day >= 1),
  voting_start_game_day BIGINT NOT NULL CHECK (voting_start_game_day >= submitted_game_day),
  voting_end_game_day BIGINT NOT NULL CHECK (voting_end_game_day >= voting_start_game_day),
  execution_game_day BIGINT,
  support_votes INTEGER NOT NULL DEFAULT 0 CHECK (support_votes >= 0),
  oppose_votes INTEGER NOT NULL DEFAULT 0 CHECK (oppose_votes >= 0),
  correlation_id TEXT NOT NULL UNIQUE,
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((subject_type = 'EARTH' AND subject_id IS NULL) OR (subject_type = 'ORGANIZATION' AND subject_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS governance_proposals_v4_subject_idx ON governance_proposals_v4 (subject_type, subject_id, status, voting_end_game_day);

CREATE TABLE IF NOT EXISTS governance_ballots_v4 (
  proposal_id TEXT NOT NULL REFERENCES governance_proposals_v4(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  cast_by_human_id TEXT NOT NULL REFERENCES humans(id),
  choice TEXT NOT NULL CHECK (choice IN ('SUPPORT', 'OPPOSE', 'ABSTAIN')),
  cast_game_day BIGINT NOT NULL CHECK (cast_game_day >= 1),
  correlation_id TEXT NOT NULL UNIQUE,
  PRIMARY KEY (proposal_id, house_id)
);
CREATE TABLE IF NOT EXISTS governance_executions_v4 (
  id TEXT PRIMARY KEY,
  proposal_id TEXT NOT NULL UNIQUE REFERENCES governance_proposals_v4(id),
  action_type TEXT NOT NULL,
  handler_version TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('PENDING', 'EXECUTED', 'FAILED')),
  result JSONB NOT NULL DEFAULT '{}'::jsonb,
  correlation_id TEXT NOT NULL UNIQUE,
  executed_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
