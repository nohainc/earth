CREATE TABLE IF NOT EXISTS personal_financial_states (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  status TEXT NOT NULL CHECK (status IN ('active','distressed','insolvent','bankrupt')),
  since_game_day INTEGER NOT NULL,
  protected_credits NUMERIC NOT NULL DEFAULT 100,
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS personal_financial_status_idx ON personal_financial_states(status, since_game_day);
