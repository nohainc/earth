CREATE TABLE IF NOT EXISTS ai_assistants (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES humans(id),
  tier TEXT NOT NULL CHECK (tier IN ('basic','business')),
  policy TEXT NOT NULL DEFAULT 'recommend',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ai_assistants_owner_idx
  ON ai_assistants(owner_id, enabled);
