ALTER TABLE businesses ADD COLUMN status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','distressed','bankrupt'));
CREATE TABLE IF NOT EXISTS financial_states (
  institution_id TEXT PRIMARY KEY,
  institution_kind TEXT NOT NULL CHECK (institution_kind IN ('BUSINESS','CITY','CORPORATION')),
  status TEXT NOT NULL CHECK (status IN ('active','distressed','insolvent','bankrupt')),
  since_game_day INTEGER NOT NULL,
  recovery_game_day INTEGER,
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS bankruptcy_events (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL,
  institution_kind TEXT NOT NULL,
  from_status TEXT NOT NULL,
  to_status TEXT NOT NULL,
  game_day INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS financial_states_status_idx ON financial_states(status, institution_kind);
