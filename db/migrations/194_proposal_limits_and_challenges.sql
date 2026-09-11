-- Proposal Engine V2: creation policy limits and explicit challenge authority.

ALTER TABLE institutions
  ADD COLUMN IF NOT EXISTS max_active_proposals_per_creator INTEGER NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS max_active_proposals_per_institution INTEGER NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS proposal_creation_cooldown_minutes INTEGER NOT NULL DEFAULT 0;

ALTER TABLE proposals ADD COLUMN IF NOT EXISTS conflict_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS proposals_active_conflict_idx
  ON proposals(conflict_key)
  WHERE conflict_key IS NOT NULL AND decision_status IN ('scheduled','voting','passed');

CREATE TABLE IF NOT EXISTS proposal_challenge_authorities (
  institution_id TEXT NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  role_code TEXT NOT NULL CHECK (role_code IN ('constitutional_judge','judicial_delegate','ouc_court')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  granted_game_day BIGINT NOT NULL DEFAULT 1,
  PRIMARY KEY (institution_id, human_id, role_code)
);
