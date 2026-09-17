-- EARTH ACTIVE MIGRATION: V5 Economic Core schema extensions

-- 1. Extend building_catalog with V5 metadata
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS design_code TEXT NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'COMMODITY' CHECK (category IN ('COMMODITY', 'SERVICE', 'RESEARCH', 'INFRASTRUCTURE')),
  ADD COLUMN IF NOT EXISTS technology_domain TEXT NOT NULL DEFAULT 'ENERGY',
  ADD COLUMN IF NOT EXISTS minimum_scale_capability TEXT NOT NULL DEFAULT 'SCALE_NONE',
  ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. Extend buildings with installed generation and lifecycle state
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS installed_generation INTEGER NOT NULL DEFAULT 1 CHECK (installed_generation > 0),
  ADD COLUMN IF NOT EXISTS catalog_definition_version TEXT NOT NULL DEFAULT 'v5-alpha-1',
  ADD COLUMN IF NOT EXISTS technology_definition_version TEXT NOT NULL DEFAULT 'tech-gen-v1',
  ADD COLUMN IF NOT EXISTS construction_state TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (construction_state IN ('ACTIVE', 'UNDER_CONSTRUCTION', 'RETROFITTING', 'INACTIVE', 'DESTROYED', 'MOTHBALLED'));

-- 3. Update economic account policies to give Corporations RESOURCE and MARKET_ESCROW accounts
INSERT INTO economic_account_policies (owner_type, account_type, allowed_asset_kind, player_visible)
VALUES
  ('CORPORATION', 'INVENTORY', 'RESOURCE', TRUE),
  ('CORPORATION', 'MARKET_ESCROW', 'ANY', TRUE)
ON CONFLICT (owner_type, account_type, allowed_asset_kind) DO NOTHING;

-- 4. Ensure technology domains exist for all 8 domains
CREATE TABLE IF NOT EXISTS technology_domains (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED'))
);

INSERT INTO technology_domains (id, code, name, description) VALUES
  ('TECH-DOMAIN-ENERGY', 'ENERGY', 'Energy Generation & Storage', 'Civilization energy generation and power infrastructure.'),
  ('TECH-DOMAIN-FOOD', 'FOOD', 'Agricultural Systems', 'Hydroponics, vertical farming, and biological consumables.'),
  ('TECH-DOMAIN-MATERIAL', 'MATERIAL', 'Materials & Refining', 'Secondary recovery, advanced metallurgy, polymers, and primary extraction.'),
  ('TECH-DOMAIN-COMPONENTS', 'COMPONENTS', 'Precision Manufacturing', 'Precision components, electronics, and electromechanical assemblies.'),
  ('TECH-DOMAIN-COMPUTE', 'COMPUTE', 'High-Density Computation', 'Compute clusters, distributed networks, and hardware architecture.'),
  ('TECH-DOMAIN-CONNECTIVITY', 'CONNECTIVITY', 'Data Networks & Communications', 'Civic data networks and high-throughput communication infrastructure.'),
  ('TECH-DOMAIN-HEALTH', 'HEALTH', 'Medical Systems & Biotechnology', 'Clinical healthcare, emergency response, and preventative medicine.'),
  ('TECH-DOMAIN-RESEARCH', 'RESEARCH', 'Scientific Discovery & Theory', 'Fundamental research methodologies and institutional laboratories.')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  status = 'ACTIVE';

-- 5. Global Technology Frontier table
CREATE TABLE IF NOT EXISTS earth_technology_frontier (
  domain_id TEXT PRIMARY KEY REFERENCES technology_domains(id),
  max_generation_number INTEGER NOT NULL DEFAULT 1 CHECK (max_generation_number >= 1),
  updated_game_day BIGINT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO earth_technology_frontier (domain_id, max_generation_number, updated_game_day)
SELECT id, 1, 1 FROM technology_domains
ON CONFLICT (domain_id) DO NOTHING;

-- 6. Corporation scale engineering capabilities
CREATE TABLE IF NOT EXISTS corporation_scale_capabilities (
  corporation_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  scale_capability TEXT NOT NULL CHECK (scale_capability IN ('SCALE_COMMERCIAL', 'SCALE_INDUSTRIAL', 'SCALE_STRATEGIC')),
  unlocked_game_day BIGINT NOT NULL DEFAULT 1,
  PRIMARY KEY (corporation_economic_id, scale_capability)
);
