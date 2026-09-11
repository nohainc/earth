-- Technology & Research V2 Plan 1: database-authoritative technology definitions.

CREATE TABLE IF NOT EXISTS technology_catalog (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN (
    'PRODUCTION', 'EFFICIENCY', 'CONSTRUCTION', 'ENERGY',
    'MAINTENANCE', 'RESEARCH', 'SERVICES', 'LOGISTICS'
  )),
  description TEXT NOT NULL,
  patentable BOOLEAN NOT NULL DEFAULT FALSE,
  patent_exclusivity_days INTEGER NOT NULL DEFAULT 0 CHECK (patent_exclusivity_days >= 0),
  research_credit_cost_units BIGINT NOT NULL CHECK (research_credit_cost_units > 0),
  research_points_required BIGINT NOT NULL CHECK (research_points_required > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'RETIRED')),
  definition_version INTEGER NOT NULL DEFAULT 1 CHECK (definition_version > 0),
  effective_from_game_day BIGINT NOT NULL DEFAULT 0 CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  UNIQUE (code, effective_from_game_day),
  UNIQUE (code, definition_version)
);

CREATE INDEX IF NOT EXISTS technology_catalog_effective_idx
  ON technology_catalog (code, effective_from_game_day DESC)
  WHERE status IN ('ACTIVE', 'SUPERSEDED');

INSERT INTO technology_catalog (
  id, code, name, category, description, patentable, patent_exclusivity_days,
  research_credit_cost_units, research_points_required, effective_from_game_day
) VALUES
  ('TECH-AUTOMATED-ASSEMBLY-V1', 'automated_assembly', 'Automated Assembly', 'PRODUCTION',
   'Improves building throughput for component and manufactured-goods production facilities.', TRUE, 3650, 24000, 100, 0),
  ('TECH-CLEAN-ENERGY-SYSTEMS-V1', 'clean_energy_systems', 'Clean Energy Systems', 'ENERGY',
   'Reduces the operating burden of energy-intensive workplaces and infrastructure.', TRUE, 3650, 32000, 100, 0),
  ('TECH-FOOD-SYNTHESIS-V1', 'food_synthesis', 'Food Synthesis', 'PRODUCTION',
   'Enables high-yield food production for resilient local supply.', TRUE, 3650, 28000, 100, 0),
  ('TECH-PREDICTIVE-MAINTENANCE-V1', 'predictive_maintenance', 'Predictive Maintenance', 'MAINTENANCE',
   'Reduces building upkeep costs when used by an eligible corporation.', TRUE, 3650, 30000, 100, 0),
  ('TECH-CIVIC-NETWORK-INFRASTRUCTURE-V1', 'civic_network_infrastructure', 'Civic Network Infrastructure', 'SERVICES',
   'Improves the coordination capacity of city services and civic institutions.', TRUE, 3650, 36000, 100, 0)
ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE technology_catalog IS
  'Authoritative, game-day-versioned Technology V2 definitions. TypeScript contains no balancing values.';
