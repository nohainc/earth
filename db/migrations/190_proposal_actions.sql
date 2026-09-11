-- Proposal Engine V2: typed, versioned proposal action records.

CREATE TABLE IF NOT EXISTS proposal_actions (
  id TEXT PRIMARY KEY,
  proposal_id TEXT NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK (sequence > 0),
  action_type TEXT NOT NULL,
  handler_version INTEGER NOT NULL DEFAULT 1,
  payload_snapshot JSONB NOT NULL,
  execution_status TEXT NOT NULL DEFAULT 'pending',
  started_game_day BIGINT,
  completed_game_day BIGINT,
  result_json JSONB,
  correlation_id TEXT NOT NULL UNIQUE,
  UNIQUE (proposal_id, sequence)
);
