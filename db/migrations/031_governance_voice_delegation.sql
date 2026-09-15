-- EARTH ACTIVE MIGRATION: governance methods, scoped delegation, and non-transferable Voice

CREATE TABLE IF NOT EXISTS organization_governance_settings (
  organization_id TEXT PRIMARY KEY REFERENCES organizations(id),
  voting_method TEXT NOT NULL DEFAULT 'ONE_HOUSE_ONE_VOTE' CHECK (voting_method IN ('ONE_HOUSE_ONE_VOTE','DELEGATED','SHARE_WEIGHTED','QUADRATIC_VOICE')),
  voice_cycle_days INTEGER NOT NULL DEFAULT 7 CHECK (voice_cycle_days BETWEEN 1 AND 30),
  voice_per_cycle INTEGER NOT NULL DEFAULT 100 CHECK (voice_per_cycle >= 0),
  updated_game_day BIGINT NOT NULL,
  updated_by_human_id TEXT NOT NULL REFERENCES humans(id)
);
CREATE TABLE IF NOT EXISTS organization_governance_delegations (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  delegator_house_id TEXT NOT NULL REFERENCES houses(id),
  delegate_house_id TEXT NOT NULL REFERENCES houses(id),
  scope TEXT NOT NULL CHECK (scope IN ('ALL','BUDGET','CHARTER','TERRITORY','RESEARCH')),
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED','EXPIRED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (delegator_house_id <> delegate_house_id),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS organization_delegations_one_active_idx
  ON organization_governance_delegations (organization_id, delegator_house_id, scope)
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;
CREATE INDEX IF NOT EXISTS organization_delegations_delegate_idx
  ON organization_governance_delegations (organization_id, delegate_house_id, scope, effective_from_game_day);
CREATE TABLE IF NOT EXISTS governance_voice_cycles (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  cycle_start_game_day BIGINT NOT NULL,
  cycle_end_game_day BIGINT NOT NULL,
  voice_total INTEGER NOT NULL CHECK (voice_total >= 0),
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  UNIQUE (organization_id, cycle_start_game_day)
);
CREATE TABLE IF NOT EXISTS governance_voice_allocations (
  cycle_id TEXT NOT NULL REFERENCES governance_voice_cycles(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  allocated_voice INTEGER NOT NULL CHECK (allocated_voice >= 0),
  spent_voice INTEGER NOT NULL DEFAULT 0 CHECK (spent_voice >= 0 AND spent_voice <= allocated_voice),
  PRIMARY KEY (cycle_id, house_id)
);
