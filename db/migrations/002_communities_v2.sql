-- EARTH ACTIVE MIGRATION: Community V2 persistence
-- Temporary reconciliation migration; fold into the next final baseline before production freeze.

CREATE TABLE communities (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  visibility TEXT NOT NULL DEFAULT 'PUBLIC' CHECK (visibility IN ('PUBLIC', 'PRIVATE')),
  join_policy TEXT NOT NULL DEFAULT 'OPEN' CHECK (join_policy IN ('OPEN', 'REQUEST')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISBANDED')),
  founder_house_id TEXT NOT NULL REFERENCES houses(id),
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  created_game_day INTEGER NOT NULL CHECK (created_game_day >= 0),
  created_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (created_game_minute >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disbanded_at TIMESTAMPTZ NULL
);

CREATE TABLE community_memberships (
  community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  house_id TEXT NOT NULL REFERENCES houses(id),
  role TEXT NOT NULL CHECK (role IN ('OWNER', 'MODERATOR', 'MEMBER')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'LEFT', 'REMOVED')),
  joined_by_human_id TEXT NOT NULL REFERENCES humans(id),
  joined_game_day INTEGER NOT NULL CHECK (joined_game_day >= 0),
  joined_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (joined_game_minute >= 0),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  left_at TIMESTAMPTZ NULL,
  PRIMARY KEY (community_id, house_id)
);

CREATE TABLE community_membership_requests (
  id TEXT PRIMARY KEY,
  community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  house_id TEXT NOT NULL REFERENCES houses(id),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
  message TEXT NOT NULL DEFAULT '',
  requested_by_human_id TEXT NOT NULL REFERENCES humans(id),
  decided_by_human_id TEXT NULL REFERENCES humans(id),
  correlation_id TEXT NOT NULL UNIQUE,
  requested_game_day INTEGER NOT NULL CHECK (requested_game_day >= 0),
  requested_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (requested_game_minute >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at TIMESTAMPTZ NULL
);

CREATE UNIQUE INDEX community_membership_requests_pending_uq
  ON community_membership_requests (community_id, house_id)
  WHERE status = 'PENDING';

CREATE INDEX communities_status_visibility_created_idx
  ON communities (status, visibility, created_at DESC);
CREATE INDEX community_memberships_house_status_idx
  ON community_memberships (house_id, status);
CREATE INDEX community_memberships_community_status_role_idx
  ON community_memberships (community_id, status, role);
CREATE INDEX community_membership_requests_community_status_created_idx
  ON community_membership_requests (community_id, status, created_at DESC);
CREATE INDEX community_membership_requests_house_status_idx
  ON community_membership_requests (house_id, status);
