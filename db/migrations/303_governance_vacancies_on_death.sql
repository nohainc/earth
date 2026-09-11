-- Death & Continuity V2 Plan 15.
CREATE TABLE IF NOT EXISTS governance_vacancies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  office_code TEXT NOT NULL,
  former_human_id TEXT NOT NULL REFERENCES humans(id),
  vacancy_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'FILLED', 'CANCELLED')),
  reason TEXT NOT NULL DEFAULT 'ENDED_BY_DEATH',
  replacement_human_id TEXT REFERENCES humans(id),
  filled_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS governance_vacancies_open_idx
  ON governance_vacancies(institution_id, status, vacancy_game_day);

ALTER TABLE proposal_challenge_authorities
  DROP CONSTRAINT IF EXISTS proposal_challenge_authorities_status_check;
ALTER TABLE proposal_challenge_authorities
  ADD CONSTRAINT proposal_challenge_authorities_status_check
  CHECK (status IN ('active', 'revoked', 'ENDED_BY_DEATH'));
