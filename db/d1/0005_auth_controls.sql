CREATE TABLE IF NOT EXISTS auth_login_attempts (
  email TEXT PRIMARY KEY,
  window_started_at TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  blocked_until TEXT
);

CREATE INDEX IF NOT EXISTS auth_login_block_idx ON auth_login_attempts(blocked_until);
