-- Migration 050: Physical Real Estate, Multi-Tier Buildings, Municipal Shared Shift Labor Pool, and Corporate R&D Commons

CREATE TABLE IF NOT EXISTS buildings (
  id TEXT PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  owner_id TEXT NOT NULL,
  ownership_type TEXT NOT NULL CHECK (ownership_type IN ('private', 'municipal', 'corporate')),
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  building_type TEXT NOT NULL,
  name TEXT NOT NULL,
  tier INTEGER NOT NULL DEFAULT 1 CHECK (tier >= 1 AND tier <= 5),
  condition NUMERIC(5,2) NOT NULL DEFAULT 100 CHECK (condition >= 0 AND condition <= 100),
  max_staff_slots INTEGER NOT NULL DEFAULT 4,
  upkeep_energy NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_food NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_materials NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_components NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_compute NUMERIC(10,2) NOT NULL DEFAULT 0,
  base_revenue_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'under_construction', 'damaged', 'closed')),
  created_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS buildings_city_idx ON buildings(city_id, status);
CREATE INDEX IF NOT EXISTS buildings_owner_idx ON buildings(owner_id, status);
CREATE INDEX IF NOT EXISTS buildings_business_idx ON buildings(business_id);

CREATE TABLE IF NOT EXISTS building_staff_assignments (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  staff_type TEXT NOT NULL CHECK (staff_type IN ('machine', 'employee')),
  machine_id TEXT REFERENCES machines(id) ON DELETE CASCADE,
  employee_id TEXT REFERENCES business_employees(id) ON DELETE CASCADE,
  assigned_by TEXT NOT NULL REFERENCES humans(id),
  assigned_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'reassigned')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_building_machine_slot UNIQUE (building_id, machine_id)
);

CREATE INDEX IF NOT EXISTS building_staff_building_idx ON building_staff_assignments(building_id, status);

CREATE TABLE IF NOT EXISTS municipal_labor_pool (
  id TEXT PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  registered_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'withdrawn')),
  accumulated_wages_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_municipal_machine UNIQUE (city_id, machine_id)
);

CREATE INDEX IF NOT EXISTS municipal_labor_city_idx ON municipal_labor_pool(city_id, status);
CREATE INDEX IF NOT EXISTS municipal_labor_human_idx ON municipal_labor_pool(human_id, status);

CREATE TABLE IF NOT EXISTS corporate_research_pools (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  technology_key TEXT NOT NULL,
  name TEXT NOT NULL,
  target_compute NUMERIC(20,2) NOT NULL,
  target_credits NUMERIC(20,2) NOT NULL,
  contributed_compute NUMERIC(20,2) NOT NULL DEFAULT 0,
  contributed_credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed')),
  started_game_day BIGINT NOT NULL,
  completed_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_corp_tech_pool UNIQUE (corporation_id, technology_key)
);

CREATE INDEX IF NOT EXISTS corporate_research_corp_idx ON corporate_research_pools(corporation_id, status);

-- Seed Initial Municipal Megaprojects for Canonical Cities
INSERT INTO buildings (id, city_id, owner_id, ownership_type, building_type, name, tier, condition, max_staff_slots, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, base_revenue_crd, status, created_game_day)
SELECT 'BLD-MUNI-GEO-0084', 'CITY-0084', 'CITY-0084', 'municipal', 'geothermal-grid', 'New Carthage Central Geothermal Grid', 3, 98.0, 12, 0.0, 0.0, 1.5, 0.5, 0.2, 850.0, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM buildings WHERE id = 'BLD-MUNI-GEO-0084');

INSERT INTO buildings (id, city_id, owner_id, ownership_type, building_type, name, tier, condition, max_staff_slots, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, base_revenue_crd, status, created_game_day)
SELECT 'BLD-MUNI-LOG-0084', 'CITY-0084', 'CITY-0084', 'municipal', 'transit-terminus', 'New Carthage Central Transit Hub', 2, 95.0, 16, 2.0, 0.0, 0.5, 0.8, 0.5, 1200.0, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM buildings WHERE id = 'BLD-MUNI-LOG-0084');

INSERT INTO buildings (id, city_id, owner_id, ownership_type, building_type, name, tier, condition, max_staff_slots, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, base_revenue_crd, status, created_game_day)
SELECT 'BLD-MUNI-HOSP-0084', 'CITY-0084', 'CITY-0084', 'municipal', 'general-hospital', 'New Carthage Metropolitan Medical Center', 2, 99.0, 10, 3.0, 1.5, 0.2, 1.0, 1.0, 600.0, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM buildings WHERE id = 'BLD-MUNI-HOSP-0084');

-- Seed Starter Corporate Research Projects
INSERT INTO corporate_research_pools (id, corporation_id, technology_key, name, target_compute, target_credits, contributed_compute, contributed_credits, status, started_game_day)
SELECT 'CRP-CORP001-AUTO', 'CORP-001', 'automated_assembly_v2', 'Automated Molecular Assembly 2.0', 5000, 25000, 1200, 8500, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM corporate_research_pools WHERE id = 'CRP-CORP001-AUTO');

INSERT INTO corporate_research_pools (id, corporation_id, technology_key, name, target_compute, target_credits, contributed_compute, contributed_credits, status, started_game_day)
SELECT 'CRP-CORP001-ORBIT', 'CORP-001', 'orbital_logistics_v2', 'Orbital Heavy Logistics & Skyhook Grid', 8000, 45000, 2100, 15000, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM corporate_research_pools WHERE id = 'CRP-CORP001-ORBIT');
