CREATE TABLE IF NOT EXISTS negotiated_contracts (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('employment','intellectual_service','capacity','strategic')),
  proposer_id TEXT NOT NULL REFERENCES humans(id),
  counterparty_id TEXT NOT NULL REFERENCES humans(id),
  title TEXT NOT NULL,
  terms_json TEXT NOT NULL DEFAULT '{}',
  amount NUMERIC NOT NULL DEFAULT 0 CHECK (amount >= 0),
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','accepted','cancelled','completed')),
  starts_game_day INTEGER NOT NULL,
  ends_game_day INTEGER NOT NULL,
  accepted_game_day INTEGER,
  correlation_id TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (proposer_id != counterparty_id)
);
CREATE INDEX IF NOT EXISTS negotiated_contracts_party_idx ON negotiated_contracts(proposer_id, counterparty_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS negotiated_contracts_correlation_idx ON negotiated_contracts(proposer_id, correlation_id) WHERE correlation_id IS NOT NULL;
