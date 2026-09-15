-- EARTH ACTIVE MIGRATION: idempotent matching-pool authorization events

CREATE TABLE IF NOT EXISTS public_project_matching_funds (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES public_projects(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  authorized_game_day BIGINT NOT NULL,
  proposal_id TEXT NOT NULL REFERENCES governance_proposals_v4(id),
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS public_project_matching_funds_project_idx ON public_project_matching_funds (project_id, authorized_game_day DESC);
