-- Migration 049: Community descriptions, admission policies, role management, and membership requests.

ALTER TABLE communities
  ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS admission_policy TEXT NOT NULL DEFAULT 'open'
    CHECK (admission_policy IN ('open', 'approval'));

-- Allow 'admin' role in community_members
ALTER TABLE community_members DROP CONSTRAINT IF EXISTS community_members_role_check;
ALTER TABLE community_members ADD CONSTRAINT community_members_role_check CHECK (role IN ('founder', 'admin', 'member'));

CREATE TABLE IF NOT EXISTS community_membership_requests (
  id TEXT PRIMARY KEY,
  community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_game_day BIGINT NOT NULL,
  decided_game_day BIGINT,
  decided_by TEXT REFERENCES humans(id),
  UNIQUE (community_id, human_id, status)
);

CREATE INDEX IF NOT EXISTS community_membership_requests_comm_idx
  ON community_membership_requests(community_id, status, requested_game_day);

CREATE INDEX IF NOT EXISTS community_membership_requests_human_idx
  ON community_membership_requests(human_id, status, requested_game_day);
