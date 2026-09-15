-- EARTH ACTIVE MIGRATION: generic overlapping Organization core

CREATE TABLE IF NOT EXISTS organizations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  archetype TEXT NOT NULL CHECK (archetype IN ('COMMUNITY', 'CORPORATION', 'COOPERATIVE', 'PUBLIC_BODY', 'RESEARCH', 'BANK')),
  join_policy TEXT NOT NULL DEFAULT 'OPEN' CHECK (join_policy IN ('OPEN', 'REQUEST', 'INVITE_ONLY')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DISSOLVED')),
  founder_house_id TEXT NOT NULL REFERENCES houses(id),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS organization_memberships (
  id BIGSERIAL PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  role_code TEXT NOT NULL DEFAULT 'MEMBER',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'LEFT', 'REMOVED')),
  joined_game_day BIGINT NOT NULL CHECK (joined_game_day >= 1),
  left_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (left_game_day IS NULL OR left_game_day >= joined_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS organization_memberships_active_uq ON organization_memberships (organization_id, house_id) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS organization_memberships_house_idx ON organization_memberships (house_id, status, joined_game_day DESC);
CREATE TABLE IF NOT EXISTS organization_capabilities (
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  capability_code TEXT NOT NULL CHECK (capability_code IN ('ECONOMIC_OWNER', 'GOVERNANCE', 'TERRITORY_GOVERNOR', 'RESEARCH', 'BANKING', 'PUBLIC_PROJECTS')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED')),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  rules_version TEXT NOT NULL,
  PRIMARY KEY (organization_id, capability_code)
);
CREATE TABLE IF NOT EXISTS organization_membership_requests (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
  requested_game_day BIGINT NOT NULL CHECK (requested_game_day >= 1),
  decided_game_day BIGINT,
  decided_by_house_id TEXT REFERENCES houses(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS organization_membership_requests_pending_uq ON organization_membership_requests (organization_id, house_id) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS organization_membership_requests_org_idx ON organization_membership_requests (organization_id, status, requested_game_day);
