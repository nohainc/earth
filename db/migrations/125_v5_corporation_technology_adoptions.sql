-- EARTH ACTIVE MIGRATION: V5 Corporation Technology Generations

CREATE TABLE IF NOT EXISTS corporation_technology_generations (
  corporation_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  domain_id TEXT NOT NULL REFERENCES technology_domains(id),
  generation_number INTEGER NOT NULL CHECK (generation_number >= 1),
  unlocked_game_day BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, domain_id, generation_number)
);

CREATE INDEX IF NOT EXISTS corporation_technology_generations_lookup_idx
  ON corporation_technology_generations (corporation_economic_id, domain_id, generation_number);
