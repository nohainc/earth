CREATE TABLE IF NOT EXISTS contract_disputes (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES negotiated_contracts(id),
  claimant_id TEXT NOT NULL REFERENCES humans(id),
  respondent_id TEXT NOT NULL REFERENCES humans(id),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','rejected')),
  outcome TEXT CHECK (outcome IN ('uphold','void')),
  resolved_by TEXT REFERENCES humans(id),
  resolved_game_day INTEGER,
  resolution TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS open_contract_dispute_idx ON contract_disputes(contract_id) WHERE status = 'open';
