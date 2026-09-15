-- EARTH ACTIVE MIGRATION: source-backed commons revenue allocation

CREATE TABLE IF NOT EXISTS commons_dividend_policies (
  territory_id TEXT PRIMARY KEY REFERENCES territories(id),
  reserve_bps INTEGER NOT NULL DEFAULT 5000 CHECK (reserve_bps BETWEEN 0 AND 10000),
  dividend_bps INTEGER NOT NULL DEFAULT 5000 CHECK (dividend_bps BETWEEN 0 AND 10000),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  authority_institution_id TEXT NOT NULL,
  rules_version TEXT NOT NULL DEFAULT 'commons-dividend-v1',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','RETIRED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (reserve_bps + dividend_bps <= 10000)
);

CREATE TABLE IF NOT EXISTS commons_dividend_declarations (
  id TEXT PRIMARY KEY,
  territory_id TEXT NOT NULL REFERENCES territories(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  revenue_units BIGINT NOT NULL CHECK (revenue_units >= 0),
  reserve_units BIGINT NOT NULL CHECK (reserve_units >= 0),
  distributable_units BIGINT NOT NULL CHECK (distributable_units >= 0),
  policy_snapshot JSONB NOT NULL CHECK (jsonb_typeof(policy_snapshot) = 'object'),
  beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  status TEXT NOT NULL DEFAULT 'DECLARED' CHECK (status IN ('DECLARED','SETTLED','BLOCKED','CANCELLED')),
  declared_by_human_id TEXT NOT NULL REFERENCES humans(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (territory_id, game_day)
);

CREATE TABLE IF NOT EXISTS commons_dividend_payments (
  id TEXT PRIMARY KEY,
  declaration_id TEXT NOT NULL REFERENCES commons_dividend_declarations(id),
  territory_id TEXT NOT NULL REFERENCES territories(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  eligible_slot_quantity BIGINT NOT NULL CHECK (eligible_slot_quantity > 0),
  amount_units BIGINT NOT NULL CHECK (amount_units >= 0),
  remainder_units BIGINT NOT NULL DEFAULT 0 CHECK (remainder_units >= 0),
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  status TEXT NOT NULL DEFAULT 'PAID' CHECK (status IN ('PAID','BLOCKED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (declaration_id, house_id)
);

CREATE INDEX IF NOT EXISTS commons_dividend_declarations_status_idx
  ON commons_dividend_declarations (status, game_day, territory_id);
CREATE INDEX IF NOT EXISTS commons_dividend_payments_house_idx
  ON commons_dividend_payments (house_id, created_at DESC);
