CREATE TABLE IF NOT EXISTS community_members (
  community_id TEXT NOT NULL REFERENCES communities(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('founder','member')),
  joined_game_day INTEGER NOT NULL,
  PRIMARY KEY (community_id, human_id)
);

CREATE INDEX IF NOT EXISTS community_members_human_idx ON community_members(human_id);

INSERT OR IGNORE INTO community_members (community_id, human_id, role, joined_game_day)
SELECT id, founder_id, 'founder', 160 FROM communities;
