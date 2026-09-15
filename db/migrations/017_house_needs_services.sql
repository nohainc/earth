-- EARTH ACTIVE MIGRATION: versioned House needs and service capacity

CREATE TABLE IF NOT EXISTS need_rules (
  need_code TEXT PRIMARY KEY,
  service_type_code TEXT NOT NULL,
  demand_units_per_human BIGINT NOT NULL CHECK (demand_units_per_human > 0),
  critical_threshold_bps INTEGER NOT NULL CHECK (critical_threshold_bps BETWEEN 0 AND 10000),
  rules_version TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RETIRED'))
);

CREATE TABLE IF NOT EXISTS service_types (
  code TEXT PRIMARY KEY,
  payer_scope TEXT NOT NULL CHECK (payer_scope IN ('HOUSE', 'EARTH', 'CORPORATION')),
  daily_price_units BIGINT NOT NULL CHECK (daily_price_units >= 0),
  allocation_priority INTEGER NOT NULL CHECK (allocation_priority >= 0),
  rules_version TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RETIRED'))
);

CREATE TABLE IF NOT EXISTS house_need_assessments (
  house_id TEXT NOT NULL REFERENCES houses(id),
  game_day BIGINT NOT NULL,
  need_code TEXT NOT NULL REFERENCES need_rules(need_code),
  demand_units BIGINT NOT NULL CHECK (demand_units >= 0),
  available_units BIGINT NOT NULL CHECK (available_units >= 0),
  allocated_units BIGINT NOT NULL CHECK (allocated_units >= 0),
  shortfall_units BIGINT NOT NULL CHECK (shortfall_units >= 0),
  risk_level TEXT NOT NULL CHECK (risk_level IN ('NORMAL', 'WATCH', 'CRITICAL')),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (house_id, game_day, need_code),
  CHECK (allocated_units <= demand_units),
  CHECK (shortfall_units = demand_units - allocated_units)
);

CREATE TABLE IF NOT EXISTS service_allocations (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  territory_id TEXT NOT NULL REFERENCES territories(id),
  service_code TEXT NOT NULL REFERENCES service_types(code),
  provider_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  payer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL,
  capacity_units BIGINT NOT NULL CHECK (capacity_units > 0),
  allocated_units BIGINT NOT NULL CHECK (allocated_units > 0),
  price_units BIGINT NOT NULL CHECK (price_units >= 0),
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (house_id, service_code, game_day, provider_economic_id)
);

CREATE INDEX IF NOT EXISTS house_need_assessments_day_idx ON house_need_assessments (game_day, house_id);
CREATE INDEX IF NOT EXISTS service_allocations_provider_day_idx ON service_allocations (provider_economic_id, game_day);

INSERT INTO service_types (code, payer_scope, daily_price_units, allocation_priority, rules_version) VALUES
  ('HOUSING', 'HOUSE', 0, 10, 'services-v1'),
  ('ENERGY', 'HOUSE', 1, 20, 'services-v1'),
  ('CONNECTIVITY', 'HOUSE', 1, 30, 'services-v1'),
  ('HEALTH', 'HOUSE', 1, 40, 'services-v1')
ON CONFLICT (code) DO UPDATE SET payer_scope = EXCLUDED.payer_scope, daily_price_units = EXCLUDED.daily_price_units, allocation_priority = EXCLUDED.allocation_priority, rules_version = EXCLUDED.rules_version, status = 'ACTIVE';

INSERT INTO need_rules (need_code, service_type_code, demand_units_per_human, critical_threshold_bps, rules_version) VALUES
  ('HOUSING', 'HOUSING', 1, 7500, 'needs-v1'),
  ('ENERGY', 'ENERGY', 1, 7500, 'needs-v1'),
  ('CONNECTIVITY', 'CONNECTIVITY', 1, 7500, 'needs-v1'),
  ('HEALTH', 'HEALTH', 1, 7500, 'needs-v1')
ON CONFLICT (need_code) DO UPDATE SET service_type_code = EXCLUDED.service_type_code, demand_units_per_human = EXCLUDED.demand_units_per_human, critical_threshold_bps = EXCLUDED.critical_threshold_bps, rules_version = EXCLUDED.rules_version, status = 'ACTIVE';
