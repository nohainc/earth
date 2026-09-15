-- EARTH ACTIVE MIGRATION: Organization-owned technology adoption

CREATE TABLE IF NOT EXISTS organization_technology_adoptions (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  generation_id TEXT NOT NULL REFERENCES technology_generations(id),
  authorization_proposal_id TEXT NOT NULL REFERENCES governance_proposals_v4(id),
  status TEXT NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','ADOPTED','RETIRED','REJECTED')),
  adoption_cost_units BIGINT NOT NULL CHECK (adoption_cost_units >= 0),
  adopted_game_day BIGINT,
  effective_from_game_day BIGINT,
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (organization_id, generation_id)
);

CREATE INDEX IF NOT EXISTS organization_technology_adoptions_org_status_idx
  ON organization_technology_adoptions (organization_id, status, effective_from_game_day);
