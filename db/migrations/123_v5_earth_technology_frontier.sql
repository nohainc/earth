-- EARTH ACTIVE MIGRATION: V5 Earth Technology Frontier

-- Frontier changes are immutable, future-effective records.  The existing
-- earth_technology_frontier table remains the compact current-day projection;
-- this history is the authoritative audit trail for governance and replay.
CREATE TABLE IF NOT EXISTS earth_technology_frontier_versions (
  id TEXT PRIMARY KEY,
  domain_id TEXT NOT NULL REFERENCES technology_domains(id),
  generation_number INTEGER NOT NULL CHECK (generation_number >= 1),
  predecessor_generation_number INTEGER CHECK (predecessor_generation_number IS NULL OR predecessor_generation_number >= 1),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  research_credit_cost_units BIGINT NOT NULL DEFAULT 0 CHECK (research_credit_cost_units >= 0),
  research_resource_costs JSONB NOT NULL DEFAULT '{}'::JSONB,
  authorization_proposal_id TEXT,
  rules_version TEXT NOT NULL DEFAULT 'earth-technology-frontier-v1',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RETIRED')),
  created_by_human_id TEXT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (domain_id, generation_number),
  UNIQUE (domain_id, effective_from_game_day)
);

INSERT INTO earth_technology_frontier_versions
  (id, domain_id, generation_number, effective_from_game_day, correlation_id)
SELECT 'EARTH-FRONTIER-' || d.id || '-1', d.id, 1, 1,
       'earth-frontier-bootstrap:' || d.id
  FROM technology_domains d
 WHERE d.status = 'ACTIVE'
ON CONFLICT (domain_id, generation_number) DO NOTHING;

CREATE INDEX IF NOT EXISTS earth_technology_frontier_versions_effective_idx
  ON earth_technology_frontier_versions (domain_id, effective_from_game_day DESC);
