-- Formal social gameplay: alliances, negotiations, campaigns, announcements,
-- lobbying, shared projects, and diplomatic agreements.
CREATE TABLE IF NOT EXISTS social_initiatives (
  id TEXT PRIMARY KEY,
  creator_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  target_human_id TEXT REFERENCES humans(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('alliance','negotiation','campaign','announcement','lobbying','shared_project','agreement')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','active','accepted','declined','completed','expired')),
  terms JSONB NOT NULL DEFAULT '{}'::jsonb,
  deadline_game_day INT,
  escrow_amount NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (escrow_amount >= 0),
  escrow_status TEXT NOT NULL DEFAULT 'none' CHECK (escrow_status IN ('none','locked','released','forfeited')),
  reputation_delta INT NOT NULL DEFAULT 0,
  progress INT NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  game_day INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS social_initiative_members (
  initiative_id TEXT NOT NULL REFERENCES social_initiatives(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'participant',
  status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','accepted','declined','completed')),
  contribution INT NOT NULL DEFAULT 0,
  PRIMARY KEY (initiative_id, human_id)
);
CREATE INDEX IF NOT EXISTS social_initiatives_participant_idx ON social_initiative_members(human_id, status);
CREATE INDEX IF NOT EXISTS social_initiatives_kind_status_idx ON social_initiatives(kind, status, game_day DESC);
