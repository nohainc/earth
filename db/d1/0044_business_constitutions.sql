CREATE TABLE IF NOT EXISTS business_constitutions (
  business_id TEXT PRIMARY KEY REFERENCES businesses(id),
  version INTEGER NOT NULL DEFAULT 1,
  shareholder_vote_threshold NUMERIC NOT NULL DEFAULT 0.5 CHECK (shareholder_vote_threshold > 0 AND shareholder_vote_threshold <= 1),
  board_approval_threshold NUMERIC NOT NULL DEFAULT 0.5 CHECK (board_approval_threshold > 0 AND board_approval_threshold <= 1),
  dilution_notice_days INTEGER NOT NULL DEFAULT 3 CHECK (dilution_notice_days BETWEEN 0 AND 30),
  updated_by TEXT NOT NULL REFERENCES humans(id),
  updated_game_day INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO business_constitutions (business_id, updated_by, updated_game_day)
SELECT id, owner_id, COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 0)
FROM businesses;

CREATE INDEX IF NOT EXISTS business_constitutions_version_idx ON business_constitutions(version, updated_game_day);
