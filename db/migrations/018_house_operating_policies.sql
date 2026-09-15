-- EARTH ACTIVE MIGRATION: versioned House operating policies

CREATE TABLE IF NOT EXISTS house_operating_policies (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  policy_type TEXT NOT NULL CHECK (policy_type IN ('OPERATING', 'INVENTORY_RESERVE', 'MARKET_STANDING')),
  version INTEGER NOT NULL CHECK (version > 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PAUSED', 'SUPERSEDED')),
  operating_mode TEXT NOT NULL DEFAULT 'BALANCED' CHECK (operating_mode IN ('CONSERVATIVE', 'BALANCED', 'GROWTH', 'CUSTOM')),
  daily_spend_cap_units BIGINT NOT NULL DEFAULT 0 CHECK (daily_spend_cap_units >= 0),
  reserve_floor_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(reserve_floor_units) = 'object'),
  max_input_price_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(max_input_price_units) = 'object'),
  min_sale_price_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(min_sale_price_units) = 'object'),
  procurement_quantity_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(procurement_quantity_units) = 'object'),
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (house_id, policy_type, version)
);

CREATE INDEX IF NOT EXISTS house_operating_policies_active_idx
  ON house_operating_policies (house_id, policy_type, effective_from_game_day DESC)
  WHERE status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS policy_execution_log (
  id BIGSERIAL PRIMARY KEY,
  policy_id TEXT NOT NULL REFERENCES house_operating_policies(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  game_day BIGINT NOT NULL,
  action_type TEXT NOT NULL,
  action_correlation_id TEXT NOT NULL UNIQUE,
  decision JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS policy_execution_log_house_day_idx
  ON policy_execution_log (house_id, game_day DESC);
