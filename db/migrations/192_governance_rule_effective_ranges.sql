-- Proposal Engine V2: immutable, game-day-effective governance rules.

ALTER TABLE governance_rules
  ADD COLUMN IF NOT EXISTS effective_from_game_day BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS effective_to_game_day BIGINT;

COMMENT ON COLUMN governance_rules.effective_from_game_day IS 'First complete game day on which this immutable rule applies';
COMMENT ON COLUMN governance_rules.effective_to_game_day IS 'Last complete game day on which this immutable rule applies';
