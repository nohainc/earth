-- EARTH ACTIVE MIGRATION: deterministic private building settlement journals

CREATE TABLE building_settlement_journals (
  id BIGSERIAL PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id),
  house_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  utilization_bps INTEGER NOT NULL CHECK (utilization_bps BETWEEN 0 AND 10000),
  input_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(input_units) = 'object'),
  output_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(output_units) = 'object'),
  operating_credit_units BIGINT NOT NULL DEFAULT 0 CHECK (operating_credit_units >= 0),
  status TEXT NOT NULL CHECK (status IN ('OPERATED', 'PARTIAL', 'STARVED', 'SKIPPED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (building_id, game_day)
);

CREATE INDEX building_settlement_journals_house_day_idx
  ON building_settlement_journals (house_economic_id, game_day DESC);
