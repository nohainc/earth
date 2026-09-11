-- Death & Continuity V2 Plan 17.
-- Human-bound judicial authority is revoked by death and becomes unavailable
-- from the next game day; it is never inherited by the successor Human.

ALTER TABLE proposal_challenge_authorities
  ADD COLUMN IF NOT EXISTS revoked_effective_game_day BIGINT;

UPDATE proposal_challenge_authorities
SET revoked_effective_game_day = granted_game_day
WHERE status IN ('revoked', 'ENDED_BY_DEATH')
  AND revoked_effective_game_day IS NULL;

CREATE INDEX IF NOT EXISTS proposal_challenge_authorities_active_idx
  ON proposal_challenge_authorities(institution_id, role_code, status);
