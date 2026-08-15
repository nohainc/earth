CREATE TABLE IF NOT EXISTS authority_delegations (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  role_id TEXT NOT NULL REFERENCES institution_roles(id),
  delegator_id TEXT NOT NULL REFERENCES humans(id),
  delegate_id TEXT NOT NULL REFERENCES humans(id),
  starts_game_day INTEGER NOT NULL,
  ends_game_day INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked','expired')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (delegator_id != delegate_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS active_role_delegation_idx ON authority_delegations(role_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS authority_delegation_delegate_idx ON authority_delegations(delegate_id, institution_id, status);
