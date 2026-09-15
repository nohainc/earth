-- EARTH ACTIVE MIGRATION: global technology generations and discovery history

CREATE TABLE IF NOT EXISTS technology_domains (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED'))
);
CREATE TABLE IF NOT EXISTS technology_generations (
  id TEXT PRIMARY KEY,
  domain_id TEXT NOT NULL REFERENCES technology_domains(id),
  generation_number INTEGER NOT NULL CHECK (generation_number > 0),
  name TEXT NOT NULL,
  predecessor_id TEXT REFERENCES technology_generations(id),
  minimum_game_day BIGINT NOT NULL DEFAULT 1 CHECK (minimum_game_day >= 1),
  research_points_required BIGINT NOT NULL CHECK (research_points_required > 0),
  status TEXT NOT NULL DEFAULT 'LOCKED' CHECK (status IN ('LOCKED','ELIGIBLE','DISCOVERED','RETIRED')),
  UNIQUE (domain_id, generation_number)
);
CREATE TABLE IF NOT EXISTS technology_generation_effects (
  generation_id TEXT NOT NULL REFERENCES technology_generations(id),
  target_type TEXT NOT NULL CHECK (target_type IN ('BUILDING','RESOURCE','SERVICE','GLOBAL')),
  target_key TEXT NOT NULL,
  modifier_bps INTEGER NOT NULL CHECK (modifier_bps BETWEEN -10000 AND 10000),
  effect_cap_bps INTEGER CHECK (effect_cap_bps IS NULL OR effect_cap_bps BETWEEN -10000 AND 10000),
  PRIMARY KEY (generation_id, target_type, target_key)
);
CREATE TABLE IF NOT EXISTS technology_research_programs (
  id TEXT PRIMARY KEY,
  generation_id TEXT NOT NULL REFERENCES technology_generations(id),
  global_program_id TEXT NOT NULL REFERENCES global_programs(id),
  progress_points BIGINT NOT NULL DEFAULT 0 CHECK (progress_points >= 0),
  required_points BIGINT NOT NULL CHECK (required_points > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','COMPLETED','CANCELLED')),
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS technology_discoveries (
  id TEXT PRIMARY KEY,
  generation_id TEXT NOT NULL REFERENCES technology_generations(id),
  research_program_id TEXT NOT NULL REFERENCES technology_research_programs(id),
  discovered_game_day BIGINT NOT NULL,
  effective_from_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PUBLIC' CHECK (status IN ('PUBLIC','RETIRED')),
  UNIQUE (generation_id)
);
CREATE INDEX IF NOT EXISTS technology_generations_domain_idx ON technology_generations (domain_id, generation_number);
CREATE INDEX IF NOT EXISTS technology_research_programs_status_idx ON technology_research_programs (status, id);

INSERT INTO technology_domains (id, code, name, description)
VALUES ('TECH-DOMAIN-FOUNDATIONAL','FOUNDATIONAL','Foundational systems','Civilization-wide improvements to productive capacity and commons.')
ON CONFLICT (id) DO NOTHING;
INSERT INTO technology_generations (id, domain_id, generation_number, name, predecessor_id, minimum_game_day, research_points_required, status)
VALUES ('TECH-GEN-FOUNDATIONAL-1','TECH-DOMAIN-FOUNDATIONAL',1,'Foundational Generation I',NULL,1,100,'ELIGIBLE'),
       ('TECH-GEN-FOUNDATIONAL-2','TECH-DOMAIN-FOUNDATIONAL',2,'Foundational Generation II','TECH-GEN-FOUNDATIONAL-1',30,250,'LOCKED')
ON CONFLICT (id) DO NOTHING;
