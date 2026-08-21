-- Corporation research commons: patented technologies may be shared with the
-- inventor's corporation and used by its members without an external license fee.

CREATE TABLE IF NOT EXISTS corporation_technology_shares (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  patent_id TEXT NOT NULL REFERENCES patents(id),
  shared_by_human_id TEXT NOT NULL REFERENCES humans(id),
  shared_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_corporation_shared_patent UNIQUE (corporation_id, patent_id)
);

CREATE INDEX IF NOT EXISTS corporation_technology_shares_member_idx
  ON corporation_technology_shares(corporation_id, status);
