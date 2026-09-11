-- Proposal Engine V2: freeze electorate boundaries and aggregate ballots.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS eligible_voter_count BIGINT,
  ADD COLUMN IF NOT EXISTS eligibility_cutoff_game_day BIGINT;

CREATE TABLE IF NOT EXISTS proposal_vote_totals (
  proposal_id TEXT PRIMARY KEY REFERENCES proposals(id) ON DELETE CASCADE,
  voter_count BIGINT NOT NULL DEFAULT 0 CHECK (voter_count >= 0),
  support_count BIGINT NOT NULL DEFAULT 0 CHECK (support_count >= 0),
  oppose_count BIGINT NOT NULL DEFAULT 0 CHECK (oppose_count >= 0),
  abstain_count BIGINT NOT NULL DEFAULT 0 CHECK (abstain_count >= 0),
  support_weight NUMERIC(20,3) NOT NULL DEFAULT 0,
  oppose_weight NUMERIC(20,3) NOT NULL DEFAULT 0,
  abstain_weight NUMERIC(20,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO proposal_vote_totals (proposal_id, voter_count, support_count, oppose_count, abstain_count, support_weight, oppose_weight, abstain_weight)
SELECT proposal_id, COUNT(*), COUNT(*) FILTER (WHERE choice = 'support'), COUNT(*) FILTER (WHERE choice = 'oppose'), COUNT(*) FILTER (WHERE choice = 'abstain'),
       COALESCE(SUM(weight) FILTER (WHERE choice = 'support'), 0), COALESCE(SUM(weight) FILTER (WHERE choice = 'oppose'), 0), COALESCE(SUM(weight) FILTER (WHERE choice = 'abstain'), 0)
FROM ballots GROUP BY proposal_id
ON CONFLICT (proposal_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS memberships_city_joined_human_idx ON memberships(city_id, joined_game_day, human_id);
CREATE INDEX IF NOT EXISTS memberships_corporation_joined_human_idx ON memberships(corporation_id, joined_game_day, human_id);
