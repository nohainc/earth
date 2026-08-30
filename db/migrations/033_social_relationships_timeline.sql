CREATE TABLE IF NOT EXISTS social_relationships (
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  other_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  trust INT NOT NULL DEFAULT 0,
  public_reputation INT NOT NULL DEFAULT 0,
  completed_agreements INT NOT NULL DEFAULT 0,
  broken_commitments INT NOT NULL DEFAULT 0,
  last_interaction_game_day INT,
  PRIMARY KEY (human_id, other_human_id),
  CHECK (human_id <> other_human_id)
);
CREATE INDEX IF NOT EXISTS social_relationships_trust_idx ON social_relationships(human_id, trust DESC);
