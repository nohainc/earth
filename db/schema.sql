-- EARTH PostgreSQL Canonical Schema
--
-- Canonical fresh-install schema, reconciled through migration 292.
-- Numbered migrations remain the append-only upgrade history; this file is the
-- one-step fresh-install representation and is checked against the schema
-- manifest in CI.
--
-- This script provisions a fresh, empty database in one step.
-- When introducing new schema changes:
-- 1. Create a forward migration in db/migrations/NNN_description.sql
-- 2. Update this canonical db/schema.sql script to reflect the new state.
--
-- Run with: psql "" -f db/schema.sql
-- Followed by: psql "" -f db/seed.sql (if sample data is needed).

CREATE OR REPLACE FUNCTION earth_ratio_to_ppm(p_value NUMERIC)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT LEAST(1000000::BIGINT, GREATEST(0::BIGINT, ROUND(p_value * 1000000)::BIGINT));
$$;
CREATE OR REPLACE FUNCTION earth_condition_to_bp(p_value NUMERIC)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT LEAST(10000::BIGINT, GREATEST(0::BIGINT, ROUND(p_value * 100)::BIGINT));
$$;
CREATE OR REPLACE FUNCTION earth_multiplier_to_ppm(p_value NUMERIC)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT GREATEST(0::BIGINT, ROUND(p_value * 1000000)::BIGINT);
$$;
CREATE OR REPLACE FUNCTION earth_fixed_point_multiply_ppm(p_left BIGINT, p_right BIGINT)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT ROUND((p_left::NUMERIC * p_right::NUMERIC) / 1000000)::BIGINT;
$$;

-- -----------------------------------------------------------------------------
-- 1. Identity, Accounts & Authentication
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS humans (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  age_years INTEGER NOT NULL DEFAULT 31,
  standing INTEGER NOT NULL DEFAULT 0,
  legacy INTEGER NOT NULL DEFAULT 0,
  life_status TEXT NOT NULL DEFAULT 'active' CHECK (life_status IN ('active','deceased','estate')),
  death_game_day BIGINT,
  political_eligibility_game_day BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_credentials (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL DEFAULT 100000,
  email_verified_at TIMESTAMPTZ,
  mfa_secret TEXT,
  mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_sessions (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS auth_sessions_token_idx ON auth_sessions(token_hash, expires_at);

CREATE TABLE IF NOT EXISTS auth_login_attempts (
  email TEXT PRIMARY KEY,
  window_started_at TIMESTAMPTZ NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  blocked_until TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS auth_login_block_idx ON auth_login_attempts(blocked_until);

CREATE TABLE IF NOT EXISTS auth_action_tokens (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  token_hash TEXT NOT NULL UNIQUE,
  action TEXT NOT NULL CHECK (action IN ('verify_email','reset_password')),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS auth_action_tokens_lookup_idx ON auth_action_tokens(token_hash, action, expires_at);

CREATE TABLE IF NOT EXISTS auth_email_deliveries (
  id UUID PRIMARY KEY,
  action TEXT NOT NULL CHECK (action IN ('verify_email','reset_password')),
  recipient_email TEXT NOT NULL,
  human_id TEXT REFERENCES humans(id),
  delivery_status TEXT NOT NULL DEFAULT 'delivered' CHECK (delivery_status IN ('delivered','bounced','failed')),
  correlation_key TEXT,
  delivery_metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS auth_email_deliveries_recipient_idx ON auth_email_deliveries(recipient_email, created_at DESC);

-- -----------------------------------------------------------------------------
-- 2. Houses, Lineage & Life Continuity
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS houses (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  house_name TEXT NOT NULL,
  motto TEXT,
  founder_human_id TEXT REFERENCES humans(id),
  legacy_points BIGINT NOT NULL DEFAULT 0,
  total_wealth_generated NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_houses_email ON houses(email);

CREATE TABLE IF NOT EXISTS house_lineage_records (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id) ON DELETE CASCADE,
  human_id TEXT REFERENCES humans(id),
  predecessor_human_id TEXT REFERENCES humans(id),
  generation INTEGER NOT NULL,
  name TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT 'House Scion',
  birth_game_day BIGINT NOT NULL,
  death_game_day BIGINT,
  is_incumbent BOOLEAN NOT NULL DEFAULT FALSE,
  cause_of_death TEXT,
  epitaph TEXT,
  lifetime_wealth NUMERIC(20,2) NOT NULL DEFAULT 0,
  operations_completed INTEGER NOT NULL DEFAULT 0,
  proposals_authored INTEGER NOT NULL DEFAULT 0,
  legacy_score INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_house_lineage_house ON house_lineage_records(house_id, generation ASC);
CREATE INDEX IF NOT EXISTS idx_house_lineage_human ON house_lineage_records(human_id);

CREATE TABLE IF NOT EXISTS house_perks (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id) ON DELETE CASCADE,
  perk_key TEXT NOT NULL,
  perk_name TEXT NOT NULL DEFAULT '',
  perk_category TEXT NOT NULL DEFAULT '',
  tier INTEGER NOT NULL DEFAULT 1,
  unlocked_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (house_id, perk_key)
);

CREATE TABLE IF NOT EXISTS house_heirlooms (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  heirloom_type TEXT NOT NULL DEFAULT 'common',
  quality_tier TEXT NOT NULL DEFAULT 'common',
  stat_buff TEXT,
  equipped_by_human_id TEXT REFERENCES humans(id),
  inscription TEXT,
  acquired_game_day BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS succession_plans (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  successor_name TEXT NOT NULL,
  registered_game_day BIGINT NOT NULL,
  estate_period_days INTEGER NOT NULL DEFAULT 30,
  successor_human_id TEXT REFERENCES humans(id)
);

CREATE TABLE IF NOT EXISTS life_events (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('birth','death','inheritance')),
  game_day BIGINT NOT NULL,
  successor_name TEXT,
  estate_credits NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (estate_credits >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS life_events_human_idx ON life_events(human_id, game_day DESC);

CREATE TABLE IF NOT EXISTS deceased_profiles (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  display_name TEXT NOT NULL,
  death_game_day BIGINT NOT NULL,
  final_standing INTEGER NOT NULL,
  final_legacy INTEGER NOT NULL,
  successor_name TEXT,
  birth_game_day BIGINT,
  cause_of_death TEXT,
  epitaph TEXT,
  lifetime_dividends NUMERIC(20,2) NOT NULL DEFAULT 0,
  predecessor_human_id TEXT REFERENCES humans(id),
  house_name TEXT,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS human_life_conditions (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  health_status TEXT NOT NULL DEFAULT 'thriving' CHECK (health_status IN ('thriving','stable','critical','deceased')),
  consecutive_missed_days INTEGER NOT NULL DEFAULT 0 CHECK (consecutive_missed_days >= 0),
  last_maintenance_day BIGINT,
  auto_maintenance_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS personal_life_maintenance (
  id UUID PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  game_day BIGINT NOT NULL,
  food_cost NUMERIC(20,6) NOT NULL DEFAULT 0,
  energy_cost NUMERIC(20,6) NOT NULL DEFAULT 0,
  credits_spent NUMERIC(20,2) NOT NULL DEFAULT 0,
  health_status TEXT NOT NULL DEFAULT 'stable' CHECK (health_status IN ('thriving','stable','critical','deceased')),
  consecutive_missed_days INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (human_id, game_day)
);
CREATE INDEX IF NOT EXISTS personal_life_maintenance_lookup_idx ON personal_life_maintenance(human_id, game_day DESC);

-- -----------------------------------------------------------------------------
-- 3. World State & Configuration
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS world_state (
  id TEXT PRIMARY KEY,
  game_day BIGINT NOT NULL,
  game_minute INTEGER NOT NULL DEFAULT 0,
  health INTEGER NOT NULL DEFAULT 68,
  market_batch_seconds INTEGER NOT NULL DEFAULT 498,
  living_cost_index NUMERIC(10,4) NOT NULL DEFAULT 1.0,
  essential_services_index NUMERIC(10,4) NOT NULL DEFAULT 0.68,
  genesis_at TIMESTAMPTZ NOT NULL DEFAULT '2026-01-01T00:00:00Z',
  simulated_day_offset BIGINT NOT NULL DEFAULT 0,
  clock_mode TEXT NOT NULL DEFAULT 'realtime' CHECK (clock_mode IN ('realtime', 'manual', 'paused')),
  manual_total_game_minutes BIGINT NOT NULL DEFAULT 0 CHECK (manual_total_game_minutes >= 0),
  scheduler_heartbeat_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS world_events (
  id TEXT PRIMARY KEY,
  game_day BIGINT NOT NULL,
  event_type TEXT NOT NULL,
  title TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS world_events_day_idx ON world_events(game_day DESC);

CREATE TABLE IF NOT EXISTS rankings_snapshots (
  id TEXT PRIMARY KEY,
  game_day BIGINT NOT NULL,
  ranking_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  rank INTEGER NOT NULL,
  score NUMERIC(20,6) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (game_day, ranking_type, entity_id)
);
CREATE INDEX IF NOT EXISTS rankings_snapshots_type_idx ON rankings_snapshots(ranking_type, game_day DESC, rank);

CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  notification_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  entity_id TEXT,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS notifications_human_idx ON notifications(human_id, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(human_id, created_at DESC) WHERE read_at IS NULL;

-- -----------------------------------------------------------------------------
-- 4. Financial Architecture & Ledger
-- -----------------------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS owner_registry_economic_id_seq
  AS BIGINT START WITH 1001 INCREMENT BY 1 MINVALUE 1;

CREATE TABLE IF NOT EXISTS owner_registry (
  id TEXT PRIMARY KEY,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('human','city','corporation','community','system','legacy')),
  source_id TEXT NOT NULL UNIQUE,
  economic_id BIGINT NOT NULL DEFAULT nextval('owner_registry_economic_id_seq'),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed','archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (economic_id),
  CHECK (id = source_id)
);
CREATE INDEX IF NOT EXISTS owner_registry_economic_type_idx
  ON owner_registry (economic_id, owner_type, status);

CREATE TABLE IF NOT EXISTS economic_assets (
  id SMALLINT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE CHECK (code IN ('CREDIT','MATERIAL','COMPONENTS','ENERGY','COMPUTE','FOOD')),
  unit_scale BIGINT NOT NULL CHECK (unit_scale IN (100, 1000000)),
  scale BIGINT NOT NULL CHECK (scale IN (100, 1000000)),
  decimals SMALLINT NOT NULL CHECK ((scale = 100 AND decimals = 2) OR (scale = 1000000 AND decimals = 6)),
  is_currency BOOLEAN NOT NULL DEFAULT FALSE
);
INSERT INTO economic_assets (id, code, unit_scale, scale, decimals, is_currency) VALUES
  (1, 'CREDIT', 100, 100, 2, TRUE), (2, 'MATERIAL', 1000000, 1000000, 6, FALSE),
  (3, 'COMPONENTS', 1000000, 1000000, 6, FALSE), (4, 'ENERGY', 1000000, 1000000, 6, FALSE),
  (5, 'COMPUTE', 1000000, 1000000, 6, FALSE), (6, 'FOOD', 1000000, 1000000, 6, FALSE)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS market_instruments (
  id TEXT PRIMARY KEY,
  symbol TEXT NOT NULL UNIQUE,
  instrument_type TEXT NOT NULL CHECK (instrument_type IN ('SPOT', 'DELIVERY_FUTURE')),
  base_asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  quote_asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  expiry_total_game_minute BIGINT,
  lot_size_units BIGINT NOT NULL CHECK (lot_size_units > 0),
  price_tick_units BIGINT NOT NULL CHECK (price_tick_units > 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'halted', 'closed', 'expired', 'settled')),
  rules_version TEXT NOT NULL DEFAULT 'market-v2',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (instrument_type = 'SPOT' OR expiry_total_game_minute IS NOT NULL),
  CHECK (instrument_type = 'DELIVERY_FUTURE' OR expiry_total_game_minute IS NULL)
);
CREATE INDEX IF NOT EXISTS market_instruments_active_symbol_idx ON market_instruments (status, symbol);
CREATE INDEX IF NOT EXISTS market_instruments_expiry_idx ON market_instruments (expiry_total_game_minute) WHERE instrument_type = 'DELIVERY_FUTURE';
INSERT INTO market_instruments
  (id, symbol, instrument_type, base_asset_id, quote_asset_id, expiry_total_game_minute, lot_size_units, price_tick_units, status, rules_version)
VALUES
  ('SPOT-MATERIAL', 'SPOT-MATERIAL', 'SPOT', 2, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-COMPONENTS', 'SPOT-COMPONENTS', 'SPOT', 3, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-ENERGY', 'SPOT-ENERGY', 'SPOT', 4, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-COMPUTE', 'SPOT-COMPUTE', 'SPOT', 5, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-FOOD', 'SPOT-FOOD', 'SPOT', 6, 1, NULL, 1000000, 1, 'active', 'market-v2')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS economic_account_types (
  id SMALLINT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  allows_negative BOOLEAN NOT NULL DEFAULT FALSE,
  is_system_type BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT NOT NULL
);
INSERT INTO economic_account_types (id, code, allows_negative, is_system_type, description) VALUES
  (1, 'WALLET', FALSE, FALSE, 'Personal CREDIT account'),
  (2, 'INVENTORY', FALSE, FALSE, 'Physical asset inventory'),
  (3, 'TREASURY', FALSE, FALSE, 'Institutional CREDIT treasury'),
  (4, 'OPERATIONS', FALSE, FALSE, 'Operating account for institutional costs'),
  (5, 'RESERVE', FALSE, FALSE, 'Held reserve account'),
  (6, 'ESCROW', FALSE, FALSE, 'Temporarily restricted account'),
  (7, 'ISSUANCE', TRUE, TRUE, 'World source for explicitly created assets'),
  (8, 'CONSUMPTION_SINK', FALSE, TRUE, 'World sink for consumed assets'),
  (9, 'MARKET_CLEARING', FALSE, TRUE, 'Temporary market clearing account'),
  (10, 'BANK_RESERVE', FALSE, TRUE, 'Bank reserve backing banking operations')
ON CONFLICT (id) DO NOTHING;

INSERT INTO owner_registry (id, owner_type, source_id, economic_id)
VALUES ('SYSTEM', 'system', 'SYSTEM', 2), ('OUC', 'system', 'OUC', 1),
       ('SYSTEM-MONETARY-AUTHORITY', 'system', 'SYSTEM-MONETARY-AUTHORITY', DEFAULT),
       ('SYSTEM-MONETARY-RETIREMENT', 'system', 'SYSTEM-MONETARY-RETIREMENT', DEFAULT),
       ('SYSTEM-GLOBAL-BANK', 'system', 'SYSTEM-GLOBAL-BANK', DEFAULT)
ON CONFLICT (id) DO NOTHING;
INSERT INTO owner_registry (id, owner_type, source_id)
SELECT id, 'human', id FROM humans
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS account_balances (
  account_id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  balance NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  currency TEXT NOT NULL DEFAULT 'CREDIT'
);
INSERT INTO account_balances (account_id, owner_id, balance, currency)
VALUES ('account-global-corporate-bank', 'GLOBAL-CORPORATE-BANK', 0, 'CREDIT')
ON CONFLICT (account_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS ledger_entries (
  id UUID PRIMARY KEY,
  game_day BIGINT NOT NULL,
  debit_account TEXT NOT NULL,
  credit_account TEXT NOT NULL,
  amount NUMERIC(20,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL DEFAULT 'CREDIT',
  reason_type TEXT NOT NULL,
  reason_id TEXT,
  rule_version TEXT NOT NULL DEFAULT 'v0.1',
  correlation_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ledger_game_day_idx ON ledger_entries(game_day);
CREATE INDEX IF NOT EXISTS ledger_entries_correlation_idx ON ledger_entries(correlation_id);

CREATE TABLE IF NOT EXISTS financial_states (
  institution_id TEXT PRIMARY KEY,
  institution_kind TEXT NOT NULL CHECK (institution_kind IN ('CITY','CORPORATION')),
  status TEXT NOT NULL CHECK (status IN ('active','distressed','fiscal_stress','receivership','recovery','restructuring','insolvent','liquidation','bankrupt','dissolved')),
  since_game_day BIGINT NOT NULL,
  recovery_game_day BIGINT,
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS financial_states_status_idx ON financial_states(status, institution_kind);

CREATE TABLE IF NOT EXISTS city_fiscal_proceedings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  debtor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  status TEXT NOT NULL CHECK (status IN ('FISCAL_STRESS','RECEIVERSHIP','RECOVERY','ACTIVE','FAILED')),
  opened_game_day BIGINT NOT NULL,
  recovery_game_day BIGINT,
  resolved_game_day BIGINT,
  due_obligations_units BIGINT NOT NULL DEFAULT 0,
  treasury_units BIGINT NOT NULL DEFAULT 0,
  recovery_plan JSONB NOT NULL DEFAULT '{}'::JSONB,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (city_id, status)
);

CREATE TABLE IF NOT EXISTS corporation_insolvency_proceedings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  debtor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  status TEXT NOT NULL CHECK (status IN ('RESTRUCTURING','INSOLVENT','LIQUIDATION','DISSOLVED','FAILED')),
  opened_game_day BIGINT NOT NULL,
  liquidation_game_day BIGINT,
  resolved_game_day BIGINT,
  liabilities_units BIGINT NOT NULL DEFAULT 0,
  estate_value_units BIGINT NOT NULL DEFAULT 0,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (institution_id, status)
);

CREATE TABLE IF NOT EXISTS corporation_estate_assets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES corporation_insolvency_proceedings(id) ON DELETE CASCADE,
  account_id BIGINT,
  asset_id SMALLINT,
  asset_units BIGINT NOT NULL DEFAULT 0,
  liquidation_value_units BIGINT NOT NULL DEFAULT 0,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('economic_account','building','resource')),
  source_id TEXT NOT NULL,
  UNIQUE (proceeding_id, source_kind, source_id)
);

CREATE TABLE IF NOT EXISTS corporation_creditor_claims (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES corporation_insolvency_proceedings(id) ON DELETE CASCADE,
  creditor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  obligation_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  priority SMALLINT NOT NULL,
  amount_units BIGINT NOT NULL DEFAULT 0,
  paid_units BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PARTIAL','PAID','WRITTEN_OFF')),
  UNIQUE (proceeding_id, obligation_type, source_id)
);

CREATE TABLE IF NOT EXISTS bankruptcy_events (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL,
  institution_kind TEXT NOT NULL,
  from_status TEXT NOT NULL,
  to_status TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  reason TEXT NOT NULL,
  correlation_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS bankruptcy_events_correlation_idx ON bankruptcy_events(institution_id, correlation_id) WHERE correlation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS personal_financial_states (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  status TEXT NOT NULL CHECK (status IN ('active','distressed','insolvent','insolvency_proceeding','bankrupt')),
  since_game_day BIGINT NOT NULL,
  protected_credits NUMERIC(20,2) NOT NULL DEFAULT 100,
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS personal_financial_status_idx ON personal_financial_states(status, since_game_day);

CREATE TABLE IF NOT EXISTS bankruptcy_proceedings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  debtor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL CHECK (status IN ('OPEN', 'FROZEN', 'RESOLVED', 'FAILED')),
  opened_game_day BIGINT NOT NULL,
  resolved_game_day BIGINT,
  due_obligations_units BIGINT NOT NULL DEFAULT 0,
  liabilities_units BIGINT NOT NULL DEFAULT 0,
  realizable_assets_units BIGINT NOT NULL DEFAULT 0,
  liquid_assets_units BIGINT NOT NULL DEFAULT 0,
  estate_value_units BIGINT NOT NULL DEFAULT 0,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bankruptcy_estate_assets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES bankruptcy_proceedings(id) ON DELETE CASCADE,
  account_id BIGINT,
  asset_id SMALLINT,
  asset_units BIGINT NOT NULL DEFAULT 0,
  liquidation_value_units BIGINT NOT NULL DEFAULT 0,
  protected BOOLEAN NOT NULL DEFAULT FALSE,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('economic_account', 'building', 'resource')),
  source_id TEXT NOT NULL,
  UNIQUE (proceeding_id, source_kind, source_id)
);

CREATE TABLE IF NOT EXISTS bankruptcy_claims (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  proceeding_id BIGINT NOT NULL REFERENCES bankruptcy_proceedings(id) ON DELETE CASCADE,
  creditor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  obligation_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  priority SMALLINT NOT NULL,
  amount_units BIGINT NOT NULL DEFAULT 0 CHECK (amount_units >= 0),
  paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0 AND paid_units <= amount_units),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE', 'PARTIAL', 'PAID', 'WRITTEN_OFF')),
  UNIQUE (proceeding_id, obligation_type, source_id)
);

CREATE TABLE IF NOT EXISTS tax_rules (
  id TEXT PRIMARY KEY,
  scope TEXT NOT NULL,
  category TEXT NOT NULL,
  rate NUMERIC(10,6) NOT NULL CHECK (rate >= 0 AND rate <= 1),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS tax_rule_versions (
  id TEXT PRIMARY KEY,
  tax_rule_id TEXT NOT NULL REFERENCES tax_rules(id),
  scope TEXT NOT NULL,
  category TEXT NOT NULL,
  version INTEGER NOT NULL CHECK (version > 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  rate_bps INTEGER NOT NULL CHECK (rate_bps BETWEEN 0 AND 10000),
  tax_base_definition TEXT NOT NULL,
  beneficiary_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tax_rule_id, version),
  UNIQUE (tax_rule_id, effective_from_game_day),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS tax_rule_versions_effective_idx ON tax_rule_versions(tax_rule_id, effective_from_game_day DESC);

CREATE TABLE IF NOT EXISTS institution_budgets (
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  game_period BIGINT NOT NULL CHECK (game_period >= 0),
  category TEXT NOT NULL,
  authorized_units BIGINT NOT NULL CHECK (authorized_units >= 0),
  committed_units BIGINT NOT NULL DEFAULT 0 CHECK (committed_units >= 0),
  spent_units BIGINT NOT NULL DEFAULT 0 CHECK (spent_units >= 0),
  rule_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, game_period, category),
  CHECK (authorized_units >= committed_units),
  CHECK (committed_units >= spent_units)
);
CREATE INDEX IF NOT EXISTS institution_budgets_period_idx ON institution_budgets(game_period, institution_id, category);

CREATE TABLE IF NOT EXISTS institution_bailouts (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  bailout_kind TEXT NOT NULL CHECK (bailout_kind IN ('FISCAL', 'MONETARY')),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  source_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  target_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  economic_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  governance_authorization TEXT,
  reason TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS net_worth_snapshots (
  id UUID PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  game_day BIGINT NOT NULL,
  total_net_worth NUMERIC(20,2) NOT NULL DEFAULT 0,
  liquid_credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  shares_value NUMERIC(20,2) NOT NULL DEFAULT 0,
  material_value NUMERIC(20,2) NOT NULL DEFAULT 0,
  components_value NUMERIC(20,2) NOT NULL DEFAULT 0,
  energy_value NUMERIC(20,2) NOT NULL DEFAULT 0,
  compute_value NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (human_id, game_day)
);
CREATE INDEX IF NOT EXISTS net_worth_human_day_idx ON net_worth_snapshots(human_id, game_day DESC);

-- -----------------------------------------------------------------------------
-- 5. Commodity Markets & Derivatives
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS resource_balances (
  owner_id TEXT NOT NULL,
  resource TEXT NOT NULL CHECK (resource IN ('material','components','energy','compute','food')),
  amount NUMERIC(20,6) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  PRIMARY KEY (owner_id, resource)
);

CREATE SEQUENCE IF NOT EXISTS economic_accounts_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE TABLE IF NOT EXISTS economic_accounts (
  id BIGINT PRIMARY KEY DEFAULT nextval('economic_accounts_id_seq'),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  account_type SMALLINT NOT NULL REFERENCES economic_account_types(id),
  balance BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0 OR account_type = 7),
  is_default_settlement BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed','archived')),
  legacy_account_id TEXT,
  settlement_shard SMALLINT CHECK (settlement_shard IS NULL OR (account_type = 9 AND settlement_shard BETWEEN 0 AND 63)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_default_settlement_uq
  ON economic_accounts (owner_economic_id, asset_id) WHERE is_default_settlement;
CREATE INDEX IF NOT EXISTS economic_accounts_owner_asset_idx
  ON economic_accounts (owner_economic_id, asset_id, status);
CREATE INDEX IF NOT EXISTS economic_accounts_asset_owner_idx
  ON economic_accounts (asset_id, owner_economic_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_system_type_uq
  ON economic_accounts (owner_economic_id, asset_id, account_type)
  WHERE account_type IN (7, 8, 10) AND status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_legacy_account_uq
  ON economic_accounts (legacy_account_id) WHERE legacy_account_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS economic_accounts_shard_clearing_uq
  ON economic_accounts (owner_economic_id, asset_id, account_type, settlement_shard)
  WHERE account_type = 9 AND status = 'active' AND settlement_shard IS NOT NULL;
CREATE INDEX IF NOT EXISTS economic_accounts_shard_lookup_idx
  ON economic_accounts (settlement_shard, asset_id, account_type, status)
  WHERE settlement_shard IS NOT NULL;

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.id, FALSE,
       CASE t.id WHEN 7 THEN 'monetary-issuance' ELSE 'monetary-retirement' END
FROM owner_registry o
JOIN economic_account_types t ON t.id = CASE
  WHEN o.id = 'SYSTEM-MONETARY-AUTHORITY' THEN 7
  WHEN o.id = 'SYSTEM-MONETARY-RETIREMENT' THEN 8
END
WHERE o.id IN ('SYSTEM-MONETARY-AUTHORITY', 'SYSTEM-MONETARY-RETIREMENT')
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.legacy_account_id = CASE t.id WHEN 7 THEN 'monetary-issuance' ELSE 'monetary-retirement' END);

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.account_type, t.account_type = 3,
       CASE WHEN o.id = 'OUC' THEN 'account-ouc-' || CASE t.account_type WHEN 3 THEN 'treasury' WHEN 4 THEN 'operations' ELSE 'reserve' END
            ELSE CASE t.account_type WHEN 10 THEN 'account-global-corporate-bank' ELSE 'account-global-bank-operations' END END
FROM owner_registry o
CROSS JOIN (VALUES (3), (4), (5)) t(account_type)
WHERE o.id = 'OUC'
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = t.account_type)
UNION ALL
SELECT o.economic_id, 1, t.account_type, FALSE,
       CASE t.account_type WHEN 10 THEN 'account-global-corporate-bank' ELSE 'account-global-bank-operations' END
FROM owner_registry o CROSS JOIN (VALUES (10), (4)) t(account_type)
WHERE o.id = 'SYSTEM-GLOBAL-BANK'
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = t.account_type);

CREATE TABLE IF NOT EXISTS economic_account_migrations (
  legacy_account_id TEXT PRIMARY KEY,
  economic_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  mapping_kind TEXT NOT NULL,
  legacy_balance_units BIGINT NOT NULL,
  account_semantics TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.account_type, FALSE,
       'account-' || lower(o.owner_type) || '-' || o.id || CASE t.account_type WHEN 4 THEN '-operations' ELSE '-reserve' END
FROM owner_registry o CROSS JOIN (VALUES (4), (5)) t(account_type)
WHERE o.owner_type IN ('city', 'corporation')
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = t.account_type);

CREATE SEQUENCE IF NOT EXISTS economic_transactions_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE IF NOT EXISTS economic_entries_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE TABLE IF NOT EXISTS economic_transactions (
  id BIGINT PRIMARY KEY DEFAULT nextval('economic_transactions_id_seq'),
  correlation_id TEXT NOT NULL UNIQUE CHECK (length(btrim(correlation_id)) > 0),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  game_minute SMALLINT NOT NULL DEFAULT 0 CHECK (game_minute BETWEEN 0 AND 1439),
  transaction_kind TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_id TEXT,
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS economic_entries (
  id BIGINT NOT NULL DEFAULT nextval('economic_entries_id_seq'),
  transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id, game_day)
) PARTITION BY RANGE (game_day);
CREATE TABLE IF NOT EXISTS economic_entries_days_0000_1000 PARTITION OF economic_entries FOR VALUES FROM (0) TO (1001);
CREATE TABLE IF NOT EXISTS economic_entries_days_1001_2000 PARTITION OF economic_entries FOR VALUES FROM (1001) TO (2001);
CREATE TABLE IF NOT EXISTS economic_entries_days_2001_3000 PARTITION OF economic_entries FOR VALUES FROM (2001) TO (3001);
CREATE TABLE IF NOT EXISTS economic_entries_default PARTITION OF economic_entries DEFAULT;
CREATE INDEX IF NOT EXISTS economic_transactions_day_idx ON economic_transactions(game_day DESC, id DESC);
CREATE INDEX IF NOT EXISTS economic_transactions_source_idx ON economic_transactions(source_type, source_id, game_day DESC);
CREATE INDEX IF NOT EXISTS economic_entries_transaction_idx ON economic_entries(transaction_id, id);
CREATE INDEX IF NOT EXISTS economic_entries_account_day_idx ON economic_entries(account_id, game_day DESC, id DESC);
CREATE INDEX IF NOT EXISTS economic_entries_reason_idx ON economic_entries(reason_code, game_day DESC);

CREATE TABLE IF NOT EXISTS economic_owner_totals (
  owner_economic_id BIGINT PRIMARY KEY REFERENCES owner_registry(economic_id),
  credit_received BIGINT NOT NULL DEFAULT 0, credit_spent BIGINT NOT NULL DEFAULT 0,
  material_received BIGINT NOT NULL DEFAULT 0, material_spent BIGINT NOT NULL DEFAULT 0,
  components_received BIGINT NOT NULL DEFAULT 0, components_spent BIGINT NOT NULL DEFAULT 0,
  energy_received BIGINT NOT NULL DEFAULT 0, energy_spent BIGINT NOT NULL DEFAULT 0,
  compute_received BIGINT NOT NULL DEFAULT 0, compute_spent BIGINT NOT NULL DEFAULT 0,
  food_received BIGINT NOT NULL DEFAULT 0, food_spent BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS monetary_supply_snapshots (
  game_day BIGINT PRIMARY KEY CHECK (game_day >= 0),
  issued_total_units BIGINT NOT NULL CHECK (issued_total_units >= 0),
  retired_total_units BIGINT NOT NULL CHECK (retired_total_units >= 0),
  circulating_units BIGINT NOT NULL CHECK (circulating_units >= 0),
  escrow_units BIGINT NOT NULL CHECK (escrow_units >= 0),
  bank_reserve_units BIGINT NOT NULL CHECK (bank_reserve_units >= 0),
  institution_reserve_units BIGINT NOT NULL CHECK (institution_reserve_units >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (issued_total_units >= retired_total_units)
);
CREATE INDEX IF NOT EXISTS monetary_supply_snapshots_day_idx ON monetary_supply_snapshots (game_day DESC);

CREATE SEQUENCE IF NOT EXISTS settlement_rate_segments_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE TABLE IF NOT EXISTS settlement_rate_segments (
  id BIGINT PRIMARY KEY DEFAULT nextval('settlement_rate_segments_id_seq'),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  effective_from_minute SMALLINT NOT NULL CHECK (effective_from_minute BETWEEN 0 AND 1439),
  rate_units_per_day BIGINT NOT NULL,
  reason_code TEXT NOT NULL,
  source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (owner_economic_id, asset_id, game_day, effective_from_minute)
);
CREATE INDEX IF NOT EXISTS settlement_rate_segments_day_idx ON settlement_rate_segments(game_day, owner_economic_id, asset_id, effective_from_minute);
CREATE INDEX IF NOT EXISTS settlement_rate_segments_owner_asset_idx ON settlement_rate_segments(owner_economic_id, asset_id, game_day DESC, effective_from_minute);

CREATE SEQUENCE IF NOT EXISTS settlement_effects_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE UNLOGGED TABLE IF NOT EXISTS settlement_effects (
  id BIGINT PRIMARY KEY DEFAULT nextval('settlement_effects_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  phase TEXT NOT NULL,
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL,
  source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS settlement_effects_phase_shard_day_idx ON settlement_effects(game_day, phase, shard, id);
CREATE INDEX IF NOT EXISTS settlement_effects_owner_day_idx ON settlement_effects(owner_economic_id, game_day, asset_id);
CREATE INDEX IF NOT EXISTS settlement_effects_account_day_idx ON settlement_effects(account_id, game_day, id);
CREATE INDEX IF NOT EXISTS settlement_effects_source_idx ON settlement_effects(source_id, game_day, phase) WHERE source_id IS NOT NULL;

CREATE SEQUENCE IF NOT EXISTS settlement_effect_nets_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE UNLOGGED TABLE IF NOT EXISTS settlement_effect_nets (
  id BIGINT PRIMARY KEY DEFAULT nextval('settlement_effect_nets_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  phase TEXT NOT NULL,
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL,
  source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, phase, shard, account_id, asset_id)
);
CREATE INDEX IF NOT EXISTS settlement_effect_nets_batch_idx ON settlement_effect_nets(game_day, phase, shard, account_id);

CREATE TABLE IF NOT EXISTS resource_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_day BIGINT NOT NULL,
  game_minute INTEGER NOT NULL DEFAULT 0,
  owner_id TEXT NOT NULL,
  resource TEXT NOT NULL CHECK (resource IN ('material','components','energy','compute','food')),
  delta NUMERIC(20,6) NOT NULL,
  balance_after NUMERIC(20,6) NOT NULL CHECK (balance_after >= 0),
  reason_type TEXT NOT NULL,
  reason_id TEXT,
  correlation_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_resource_ledger_owner_day ON resource_ledger_entries(owner_id, game_day DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_resource_ledger_reason ON resource_ledger_entries(reason_type, reason_id);
CREATE INDEX IF NOT EXISTS idx_resource_ledger_resource_day ON resource_ledger_entries(resource, game_day DESC);

CREATE TABLE IF NOT EXISTS resource_rate_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  game_minute INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  trigger_event TEXT NOT NULL,
  trigger_entity_id TEXT,
  resource TEXT NOT NULL CHECK (resource IN ('credits','energy','food','material','components','compute')),
  gross_inflow NUMERIC(20,6) NOT NULL DEFAULT 0,
  gross_outflow NUMERIC(20,6) NOT NULL DEFAULT 0,
  tax_amount NUMERIC(20,6) NOT NULL DEFAULT 0,
  net_daily_rate NUMERIC(20,6) NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_rate_history_owner_day ON resource_rate_history(owner_id, game_day, created_at);
CREATE INDEX IF NOT EXISTS idx_rate_history_owner_resource_day ON resource_rate_history(owner_id, resource, game_day DESC);
CREATE INDEX IF NOT EXISTS idx_rate_history_created ON resource_rate_history(created_at DESC);

CREATE TABLE IF NOT EXISTS market_prices (
  product TEXT PRIMARY KEY,
  price NUMERIC(20,6) NOT NULL CHECK (price > 0),
  supply NUMERIC(20,6) NOT NULL DEFAULT 0,
  demand NUMERIC(20,6) NOT NULL DEFAULT 0,
  game_day BIGINT NOT NULL,
  price_units BIGINT,
  supply_units BIGINT NOT NULL DEFAULT 0,
  demand_units BIGINT NOT NULL DEFAULT 0
);

CREATE SEQUENCE IF NOT EXISTS market_order_sequence;
CREATE TABLE IF NOT EXISTS market_orders (
  id UUID PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  product TEXT NOT NULL CHECK (product IN ('material','components','energy','compute','food')),
  quantity NUMERIC(20,6) NOT NULL CHECK (quantity > 0),
  limit_price NUMERIC(20,2) NOT NULL CHECK (limit_price > 0),
  filled_quantity NUMERIC(20,6) NOT NULL DEFAULT 0 CHECK (filled_quantity >= 0),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','partial','filled','rejected','cancelled')),
  side TEXT NOT NULL DEFAULT 'buy' CHECK (side IN ('buy','sell')),
  correlation_id TEXT,

  quantity_units BIGINT,
  limit_price_units BIGINT,
  filled_quantity_units BIGINT NOT NULL DEFAULT 0,
  reserved_quote_units BIGINT NOT NULL DEFAULT 0,
  owner_economic_id BIGINT,
  instrument_id TEXT,
  filled_units BIGINT,
  eligible_batch_id BIGINT,
  sequence_no BIGINT,
  escrow_account_id BIGINT,
  reserved_base_units BIGINT NOT NULL DEFAULT 0,
  buyer_fee_bps INTEGER NOT NULL DEFAULT 0,
  seller_fee_bps INTEGER NOT NULL DEFAULT 0,
  rules_version TEXT NOT NULL DEFAULT 'market-v2',
  rules_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  submitted_game_day BIGINT,
  submitted_game_minute INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS market_orders_book_idx ON market_orders(product, status, limit_price, created_at);
CREATE INDEX IF NOT EXISTS market_orders_matching_idx ON market_orders(product, side, status, limit_price, created_at);
CREATE INDEX IF NOT EXISTS market_orders_reserved_idx ON market_orders(human_id, side, status, reserved_quote_units);
CREATE INDEX IF NOT EXISTS market_orders_instrument_batch_idx ON market_orders(instrument_id, eligible_batch_id, status, limit_price_units, sequence_no);
CREATE INDEX IF NOT EXISTS market_orders_owner_idx ON market_orders(owner_economic_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS market_orders_human_correlation_idx ON market_orders(human_id, correlation_id) WHERE correlation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS daily_settlement_profiles (
  owner_id TEXT PRIMARY KEY,
  owner_kind TEXT NOT NULL CHECK (owner_kind IN ('human', 'city', 'corporation', 'earth')),
  owner_economic_id BIGINT REFERENCES owner_registry(economic_id),
  profile_version BIGINT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'dirty' CHECK (status IN ('clean', 'dirty')),
  shard SMALLINT NOT NULL DEFAULT 0 CHECK (shard BETWEEN 0 AND 63),
  effective_game_day BIGINT NOT NULL DEFAULT 0,
  effective_from_game_day BIGINT NOT NULL DEFAULT 0,
  last_settled_game_day BIGINT NOT NULL DEFAULT 0,
  credits_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  energy_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  food_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  materials_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  components_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  compute_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  credit_units BIGINT NOT NULL DEFAULT 0,
  material_units BIGINT NOT NULL DEFAULT 0,
  components_units BIGINT NOT NULL DEFAULT 0,
  energy_units BIGINT NOT NULL DEFAULT 0,
  compute_units BIGINT NOT NULL DEFAULT 0,
  food_units BIGINT NOT NULL DEFAULT 0,
  fingerprint TEXT NOT NULL DEFAULT '',
  dirty_reason TEXT,
  input_fingerprint TEXT NOT NULL DEFAULT '',
  includes_building_economics BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS daily_settlement_profiles_due_idx
  ON daily_settlement_profiles (status, last_settled_game_day, owner_kind);
CREATE UNIQUE INDEX IF NOT EXISTS daily_settlement_profiles_economic_owner_uq
  ON daily_settlement_profiles (owner_economic_id)
  WHERE owner_economic_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS daily_settlement_profiles_v2_dirty_shard_idx
  ON daily_settlement_profiles (status, shard, owner_economic_id)
  WHERE status = 'dirty';

CREATE TABLE IF NOT EXISTS daily_settlement_profile_runs (
  owner_id TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  profile_version BIGINT NOT NULL,
  last_settled_game_day BIGINT NOT NULL,
  elapsed_days BIGINT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('shadow', 'applied')),
  expected_delta JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, game_day)
);
CREATE INDEX IF NOT EXISTS daily_settlement_profile_runs_day_idx
  ON daily_settlement_profile_runs (game_day DESC, mode);

-- -----------------------------------------------------------------------------
-- 6. Buildings & Real Estate Production
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS economic_policy_rules (
  code TEXT PRIMARY KEY,
  output_multiplier NUMERIC(8,4) NOT NULL CHECK (output_multiplier >= 0),
  cost_multiplier NUMERIC(8,4) NOT NULL CHECK (cost_multiplier >= 0),
  decay_multiplier NUMERIC(8,4) NOT NULL CHECK (decay_multiplier >= 0),
  is_selectable BOOLEAN NOT NULL DEFAULT TRUE,
  description TEXT NOT NULL
);
INSERT INTO economic_policy_rules (code, output_multiplier, cost_multiplier, decay_multiplier, description) VALUES
  ('balanced', 1.00, 1.00, 1.00, 'Normal production and operating costs'),
  ('high_output', 1.30, 1.40, 1.75, 'Higher output with higher operating cost and wear'),
  ('eco_reserve', 0.75, 0.70, 0.50, 'Reduced output and costs with lower wear'),
  ('halted', 0.00, 0.20, 0.10, 'Production halted with minimum operating cost and low residual wear'),
  ('overclock', 1.60, 1.90, 3.00, 'Extreme output with extreme operating cost and wear')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS economic_ownership_classes (
  code TEXT PRIMARY KEY,
  owner_scope TEXT NOT NULL CHECK (owner_scope IN ('human', 'city')),
  profile_scope TEXT NOT NULL CHECK (profile_scope IN ('private', 'civic')),
  description TEXT NOT NULL
);
INSERT INTO economic_ownership_classes (code, owner_scope, profile_scope, description) VALUES
  ('private', 'human', 'private', 'Human-owned economic activity'),
  ('civic', 'city', 'civic', 'City-owned civic economic activity')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS institutions (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('OUC','CORPORATION','CITY')),
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  administrator_human_id TEXT REFERENCES humans(id),
  max_active_proposals_per_creator INTEGER NOT NULL DEFAULT 5,
  max_active_proposals_per_institution INTEGER NOT NULL DEFAULT 50,
  proposal_creation_cooldown_minutes INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS cities (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL UNIQUE REFERENCES institutions(id),
  residents INTEGER NOT NULL DEFAULT 0,
  housing_capacity INTEGER NOT NULL DEFAULT 0,
  energy_capacity INTEGER NOT NULL DEFAULT 0,
  connectivity_capacity INTEGER NOT NULL DEFAULT 0,
  health_capacity INTEGER NOT NULL DEFAULT 0,
  treasury NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (treasury >= 0),
  corporation_id TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS buildings (
  id TEXT PRIMARY KEY,
  city_id TEXT REFERENCES cities(id),
  owner_id TEXT REFERENCES humans(id),
  building_type TEXT NOT NULL,
  name TEXT NOT NULL,
  tier INTEGER NOT NULL DEFAULT 1 CHECK (tier >= 1),
  condition NUMERIC(10,4) NOT NULL DEFAULT 100.0 CHECK (condition >= 0.0 AND condition <= 100.0),
  slot_footprint INTEGER NOT NULL DEFAULT 1 CHECK (slot_footprint >= 0),
  ownership_class TEXT NOT NULL REFERENCES economic_ownership_classes(code),
  operating_policy TEXT NOT NULL DEFAULT 'balanced' REFERENCES economic_policy_rules(code),
  auto_repair_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  auto_repair_target_condition NUMERIC(10,4) NOT NULL DEFAULT 90 CHECK (auto_repair_target_condition BETWEEN 0 AND 100),
  repair_priority INTEGER NOT NULL DEFAULT 100 CHECK (repair_priority BETWEEN 0 AND 1000),
  settlement_priority INTEGER NOT NULL DEFAULT 100 CHECK (settlement_priority BETWEEN 0 AND 1000),
  daily_operating_credits NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (daily_operating_credits >= 0),
  resource_output_amount NUMERIC(20,6) NOT NULL DEFAULT 0 CHECK (resource_output_amount >= 0),
  resource_output_type TEXT CHECK (resource_output_type IS NULL OR resource_output_type IN ('material','components','energy','compute','food')),
  construction_started_game_day BIGINT NOT NULL,
  construction_complete_game_day BIGINT,
  construction_progress NUMERIC(5,2) NOT NULL DEFAULT 0.0 CHECK (construction_progress >= 0.0 AND construction_progress <= 100.0),
  construction_rules_version TEXT,
  construction_technology_modifiers JSONB NOT NULL DEFAULT '{}'::JSONB,
  construction_base_duration_minutes BIGINT,
  construction_duration_minutes BIGINT,
  construction_cost_credits_units BIGINT,
  construction_cost_material_units BIGINT,
  construction_cost_components_units BIGINT,
  construction_cost_compute_units BIGINT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('under_construction','active','damaged','derelict','decommissioned')),
  operational_state TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (operational_state IN ('ACTIVE', 'DEGRADED', 'OFFLINE', 'DESTROYED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_settled_game_day BIGINT
);
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_construction_snapshot_nonnegative_ck;
ALTER TABLE buildings ADD CONSTRAINT buildings_construction_snapshot_nonnegative_ck CHECK (
  construction_base_duration_minutes IS NULL OR construction_base_duration_minutes >= 0
);
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_construction_duration_snapshot_nonnegative_ck;
ALTER TABLE buildings ADD CONSTRAINT buildings_construction_duration_snapshot_nonnegative_ck CHECK (
  construction_duration_minutes IS NULL OR construction_duration_minutes >= 0
);
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_construction_cost_snapshot_nonnegative_ck;
ALTER TABLE buildings ADD CONSTRAINT buildings_construction_cost_snapshot_nonnegative_ck CHECK (
  COALESCE(construction_cost_credits_units, 0) >= 0
  AND COALESCE(construction_cost_material_units, 0) >= 0
  AND COALESCE(construction_cost_components_units, 0) >= 0
  AND COALESCE(construction_cost_compute_units, 0) >= 0
);
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_ownership_scope_check;
ALTER TABLE buildings ADD CONSTRAINT buildings_ownership_scope_check CHECK (
  (ownership_class = 'private' AND owner_id IS NOT NULL)
  OR (ownership_class = 'civic' AND city_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_buildings_city ON buildings(city_id, status);
CREATE INDEX IF NOT EXISTS idx_buildings_owner ON buildings(owner_id, status);

CREATE TABLE IF NOT EXISTS building_settlement_journals (
  id UUID PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  city_id TEXT REFERENCES cities(id),
  day BIGINT NOT NULL,
  ownership_class TEXT NOT NULL,
  gross_revenue_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  operating_costs_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  net_surplus_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  condition_start NUMERIC(10,4) NOT NULL,
  condition_end NUMERIC(10,4) NOT NULL,
  auto_repaired BOOLEAN NOT NULL DEFAULT FALSE,
  technology_effects JSONB NOT NULL DEFAULT '{}'::JSONB,
  consumed_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  produced_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  rules_version TEXT NOT NULL DEFAULT 'building-economy-v2',
  condition_efficiency_ppm BIGINT NOT NULL DEFAULT 1000000,
  requested_inputs JSONB NOT NULL DEFAULT '{}'::JSONB,
  allocated_inputs JSONB NOT NULL DEFAULT '{}'::JSONB,
  shortages JSONB NOT NULL DEFAULT '{}'::JSONB,
  utilization_ppm BIGINT NOT NULL DEFAULT 0,
  base_output_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  actual_output_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  service_capacity_units BIGINT NOT NULL DEFAULT 0,
  service_units_sold BIGINT NOT NULL DEFAULT 0,
  gross_service_revenue_units BIGINT NOT NULL DEFAULT 0,
  operating_expense_units BIGINT NOT NULL DEFAULT 0,
  wear_points NUMERIC(20,8) NOT NULL DEFAULT 0,
  repair_requested_points NUMERIC(20,8) NOT NULL DEFAULT 0,
  repair_applied_points NUMERIC(20,8) NOT NULL DEFAULT 0,
  repair_resources JSONB NOT NULL DEFAULT '{}'::JSONB,
  status_before TEXT NOT NULL DEFAULT 'ACTIVE',
  status_after TEXT NOT NULL DEFAULT 'ACTIVE',
  economic_batch_id BIGINT,
  correlation_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (building_id, day)
);
CREATE INDEX IF NOT EXISTS idx_bldg_journal_city_day ON building_settlement_journals(city_id, day DESC);

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_physical_effects (
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  counterparty_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  effect_kind TEXT NOT NULL CHECK (effect_kind IN ('CONSUMPTION', 'PRODUCTION')),
  source_id TEXT NOT NULL,
  PRIMARY KEY (building_id, game_day, asset_id, effect_kind)
);
CREATE INDEX IF NOT EXISTS building_settlement_physical_effects_day_idx
  ON building_settlement_physical_effects (game_day, owner_economic_id, asset_id, building_id);

CREATE TABLE IF NOT EXISTS building_economic_batches (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_day BIGINT NOT NULL,
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'WAITING_FUNDS', 'POSTED', 'FAILED')),
  correlation_id TEXT NOT NULL UNIQUE,
  rules_version TEXT NOT NULL DEFAULT 'building-economy-v2',
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  effect_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  posted_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS building_economic_effects (
  batch_id BIGINT NOT NULL REFERENCES building_economic_batches(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL,
  source_id TEXT NOT NULL,
  detail JSONB NOT NULL DEFAULT '{}'::JSONB,
  PRIMARY KEY (batch_id, account_id, reason_code, source_id)
);
CREATE INDEX IF NOT EXISTS building_economic_effects_account_idx
  ON building_economic_effects (account_id, batch_id);

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_plans (
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  owner_id TEXT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  city_id TEXT REFERENCES cities(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  requirements JSONB NOT NULL DEFAULT '{}'::JSONB,
  allocated_inputs JSONB NOT NULL DEFAULT '{}'::JSONB,
  utilization NUMERIC(12,6) NOT NULL DEFAULT 0 CHECK (utilization >= 0 AND utilization <= 1),
  condition_efficiency NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (condition_efficiency >= 0),
  consumption JSONB NOT NULL DEFAULT '{}'::JSONB,
  production JSONB NOT NULL DEFAULT '{}'::JSONB,
  service_capacity BIGINT NOT NULL DEFAULT 0,
  service_sales BIGINT NOT NULL DEFAULT 0,
  operating_expenses JSONB NOT NULL DEFAULT '{}'::JSONB,
  wear NUMERIC(12,6) NOT NULL DEFAULT 0,
  repair_points NUMERIC(12,6) NOT NULL DEFAULT 0,
  condition_before NUMERIC(10,4) NOT NULL,
  condition_after NUMERIC(10,4) NOT NULL,
  status_after TEXT NOT NULL,
  policy_code TEXT NOT NULL,
  operation_mode TEXT NOT NULL DEFAULT 'SCALABLE',
  minimum_operating_ratio NUMERIC(12,6) NOT NULL DEFAULT 0,
  condition_curve_version TEXT NOT NULL DEFAULT 'v1',
  maintenance_fulfillment NUMERIC(12,6) NOT NULL DEFAULT 1,
  auto_repair_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  repair_target_condition NUMERIC(10,4) NOT NULL DEFAULT 90,
  repair_priority INTEGER NOT NULL DEFAULT 100,
  service_type TEXT,
  default_price_credit_units BIGINT NOT NULL DEFAULT 0,
  service_mode TEXT NOT NULL DEFAULT 'PRIVATE' CHECK (service_mode IN ('PRIVATE', 'PUBLIC_CONTRACT', 'FREE')),
  public_funding_units BIGINT NOT NULL DEFAULT 0,
  funding_source_account_type SMALLINT,
  operating_cost_units BIGINT NOT NULL DEFAULT 0,
  operating_cost_recipient_type TEXT NOT NULL DEFAULT 'NONE',
  operating_cost_recipient_account_id BIGINT REFERENCES economic_accounts(id),
  operational_state_before TEXT NOT NULL DEFAULT 'ACTIVE',
  operational_state_after TEXT NOT NULL DEFAULT 'ACTIVE',
  rules_version TEXT NOT NULL,
  utilization_ppm BIGINT GENERATED ALWAYS AS (earth_ratio_to_ppm(utilization)) STORED,
  condition_efficiency_ppm BIGINT GENERATED ALWAYS AS (earth_ratio_to_ppm(condition_efficiency)) STORED,
  condition_before_bp BIGINT GENERATED ALWAYS AS (earth_condition_to_bp(condition_before)) STORED,
  condition_after_bp BIGINT GENERATED ALWAYS AS (earth_condition_to_bp(condition_after)) STORED,
  wear_points_bp BIGINT GENERATED ALWAYS AS (earth_condition_to_bp(wear)) STORED,
  repair_points_bp BIGINT GENERATED ALWAYS AS (earth_condition_to_bp(repair_points)) STORED,
  maintenance_fulfillment_ppm BIGINT GENERATED ALWAYS AS (earth_ratio_to_ppm(maintenance_fulfillment)) STORED,
  repair_target_condition_bp BIGINT GENERATED ALWAYS AS (earth_condition_to_bp(repair_target_condition)) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (building_id, game_day),
  CHECK (
    utilization_ppm BETWEEN 0 AND 1000000
    AND condition_efficiency_ppm BETWEEN 0 AND 1000000
    AND condition_before_bp BETWEEN 0 AND 10000
    AND condition_after_bp BETWEEN 0 AND 10000
    AND maintenance_fulfillment_ppm BETWEEN 0 AND 1000000
  )
);
CREATE INDEX IF NOT EXISTS building_settlement_plans_shard_idx
  ON building_settlement_plans (game_day, shard, building_id);
CREATE INDEX IF NOT EXISTS building_settlement_plans_owner_idx
  ON building_settlement_plans (game_day, owner_economic_id, building_id);

CREATE TABLE IF NOT EXISTS building_condition_efficiency_curves (
  curve_version TEXT NOT NULL,
  condition_value NUMERIC(10,4) NOT NULL CHECK (condition_value BETWEEN 0 AND 100),
  efficiency NUMERIC(12,8) NOT NULL CHECK (efficiency BETWEEN 0 AND 1),
  PRIMARY KEY (curve_version, condition_value)
);
CREATE INDEX IF NOT EXISTS building_condition_efficiency_curves_version_idx
  ON building_condition_efficiency_curves (curve_version, condition_value);

CREATE SEQUENCE IF NOT EXISTS service_demand_id_seq AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE TABLE IF NOT EXISTS service_demand (
  id BIGINT PRIMARY KEY DEFAULT nextval('service_demand_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  city_id TEXT NOT NULL REFERENCES cities(id),
  payer_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  service_type TEXT NOT NULL,
  requested_units BIGINT NOT NULL CHECK (requested_units > 0),
  max_price_units BIGINT NOT NULL CHECK (max_price_units >= 0),
  priority INTEGER NOT NULL DEFAULT 100 CHECK (priority BETWEEN 0 AND 1000),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PARTIALLY_FULFILLED', 'FULFILLED', 'REJECTED', 'CANCELLED')),
  fulfilled_units BIGINT NOT NULL DEFAULT 0 CHECK (fulfilled_units >= 0 AND fulfilled_units <= requested_units),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, city_id, payer_economic_id, service_type)
);
CREATE INDEX IF NOT EXISTS service_demand_matching_idx
  ON service_demand (game_day, city_id, service_type, status, priority, payer_economic_id);
CREATE INDEX IF NOT EXISTS service_demand_payer_idx
  ON service_demand (payer_economic_id, game_day, service_type);

CREATE SEQUENCE IF NOT EXISTS service_allocation_id_seq AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE TABLE IF NOT EXISTS service_allocations (
  id BIGINT PRIMARY KEY DEFAULT nextval('service_allocation_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  demand_id BIGINT NOT NULL REFERENCES service_demand(id) ON DELETE CASCADE,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  city_id TEXT NOT NULL REFERENCES cities(id),
  service_type TEXT NOT NULL,
  delivered_units BIGINT NOT NULL CHECK (delivered_units > 0),
  price_units BIGINT NOT NULL CHECK (price_units >= 0),
  status TEXT NOT NULL DEFAULT 'RESOLVED' CHECK (status IN ('RESOLVED', 'POSTED', 'CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, demand_id, building_id)
);
CREATE INDEX IF NOT EXISTS service_allocations_group_idx
  ON service_allocations (game_day, city_id, service_type, building_id);
CREATE INDEX IF NOT EXISTS service_allocations_demand_idx
  ON service_allocations (demand_id, game_day);

CREATE TABLE IF NOT EXISTS service_payment_batches (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_day BIGINT NOT NULL,
  city_id TEXT NOT NULL REFERENCES cities(id),
  service_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'WAITING_FUNDS', 'COMPLETED', 'FAILED')),
  rules_version TEXT NOT NULL DEFAULT 'building-service-v2',
  service_settlement_id TEXT NOT NULL UNIQUE,
  correlation_id TEXT NOT NULL UNIQUE,
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  consumer_units BIGINT NOT NULL DEFAULT 0,
  operator_units BIGINT NOT NULL DEFAULT 0,
  allocation_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS service_payment_effects (
  service_settlement_id TEXT NOT NULL REFERENCES service_payment_batches(service_settlement_id) ON DELETE CASCADE,
  allocation_id BIGINT NOT NULL REFERENCES service_allocations(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  role TEXT NOT NULL CHECK (role IN ('CONSUMER', 'OPERATOR')),
  PRIMARY KEY (service_settlement_id, allocation_id, account_id)
);
CREATE INDEX IF NOT EXISTS service_payment_effects_account_idx
  ON service_payment_effects (account_id, service_settlement_id);

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_allocations (
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  requested_units BIGINT NOT NULL CHECK (requested_units >= 0),
  allocated_units BIGINT NOT NULL CHECK (allocated_units >= 0),
  allocation_remainder NUMERIC(30,12) NOT NULL DEFAULT 0,
  PRIMARY KEY (building_id, game_day, asset_id)
);
CREATE INDEX IF NOT EXISTS building_settlement_allocations_owner_idx
  ON building_settlement_allocations (game_day, owner_economic_id, asset_id, building_id);

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_owner_inputs (
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  available_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  account_ids JSONB NOT NULL DEFAULT '{}'::JSONB,
  building_count INTEGER NOT NULL DEFAULT 0 CHECK (building_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (owner_economic_id, game_day)
);
CREATE INDEX IF NOT EXISTS building_settlement_owner_inputs_shard_idx
  ON building_settlement_owner_inputs (game_day, shard, owner_economic_id);

-- -----------------------------------------------------------------------------
-- 8. Corporations, Cities, Communities & Governance
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS corporations (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL UNIQUE REFERENCES institutions(id),
  member_count INTEGER NOT NULL DEFAULT 0,
  treasury NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (treasury >= 0),
  constitution_version INTEGER NOT NULL DEFAULT 1,
  capital_city_id TEXT,
  admission_policy TEXT NOT NULL DEFAULT 'open' CHECK (admission_policy IN ('open','approval','closed')),
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS memberships (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  corporation_id TEXT REFERENCES corporations(id),
  city_id TEXT REFERENCES cities(id),
  joined_game_day BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS membership_events (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  institution_type TEXT NOT NULL,
  institution_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('joined','left','released')),
  game_day BIGINT NOT NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS membership_events_human_idx ON membership_events(human_id, game_day DESC);
CREATE INDEX IF NOT EXISTS membership_events_institution_idx ON membership_events(institution_id, game_day DESC);

CREATE TABLE IF NOT EXISTS corporation_membership_requests (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  message TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_game_day BIGINT NOT NULL,
  resolved_game_day BIGINT,
  resolution_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_corp_req_corp ON corporation_membership_requests(corporation_id, status);
CREATE INDEX IF NOT EXISTS idx_corp_req_human ON corporation_membership_requests(human_id, status);

CREATE TABLE IF NOT EXISTS budgets (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  category TEXT NOT NULL,
  amount NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  game_day BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS civic_dividend_payouts (
  id UUID PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  day BIGINT NOT NULL,
  total_civic_surplus NUMERIC(20,2) NOT NULL DEFAULT 0,
  base_dividend_per_resident NUMERIC(20,2) NOT NULL DEFAULT 0,
  participation_dividend_pool NUMERIC(20,2) NOT NULL DEFAULT 0,
  eligible_residents_count INTEGER NOT NULL DEFAULT 0,
  payout_executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (city_id, day)
);
ALTER TABLE civic_dividend_payouts
  ADD COLUMN IF NOT EXISTS economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  ADD COLUMN IF NOT EXISTS committed_obligations_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS required_reserve_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS distributable_units BIGINT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_civic_div_city_day ON civic_dividend_payouts(city_id, day DESC);

CREATE TABLE IF NOT EXISTS dividend_settlement_runs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payer_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  beneficiary_kind TEXT NOT NULL CHECK (beneficiary_kind IN ('CITY_RESIDENT', 'CORPORATION_SHAREHOLDER')),
  game_day BIGINT NOT NULL,
  gross_surplus_units BIGINT NOT NULL DEFAULT 0,
  committed_obligations_units BIGINT NOT NULL DEFAULT 0,
  required_reserve_units BIGINT NOT NULL DEFAULT 0,
  distributable_units BIGINT NOT NULL DEFAULT 0,
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  status TEXT NOT NULL CHECK (status IN ('COMPLETED', 'NO_SURPLUS', 'INSUFFICIENT_SURPLUS')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (payer_owner_economic_id, beneficiary_kind, game_day)
);

CREATE OR REPLACE VIEW financial_obligations AS
SELECT l.id::TEXT AS source_id, l.borrower_economic_id AS debtor_economic_id, bank.economic_id AS creditor_economic_id,
  'BANK_LOAN'::TEXT AS obligation_type, l.outstanding_principal_units AS principal_due_units, l.accrued_interest_units AS interest_due_units,
  COALESCE(l.next_payment_game_day, l.origination_total_game_minute / 1440) AS due_game_day, 20 AS priority_class, l.status
FROM bank_loans l JOIN owner_registry bank ON bank.id = 'SYSTEM-GLOBAL-BANK'
WHERE l.status NOT IN ('REPAID', 'WRITTEN_OFF')
UNION ALL
SELECT t.id::TEXT, t.taxpayer_economic_id, t.beneficiary_economic_id, 'TAX'::TEXT, t.amount_units, 0::BIGINT, t.game_day, 10, t.status
FROM tax_obligations t WHERE t.status NOT IN ('PAID', 'WAIVED');

CREATE TABLE IF NOT EXISTS global_bank_deposits (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  principal NUMERIC(20,2) NOT NULL CHECK (principal > 0),
  daily_rate NUMERIC(12,8) NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  accrued_interest NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (accrued_interest >= 0),
  start_game_day BIGINT NOT NULL,
  start_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (start_game_minute BETWEEN 0 AND 1439),
  maturity_game_day BIGINT NOT NULL CHECK (maturity_game_day >= start_game_day),
  maturity_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (maturity_game_minute BETWEEN 0 AND 1439),
  last_settled_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','matured','withdrawn','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS global_bank_deposits_human_idx ON global_bank_deposits(human_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS global_bank_loans (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  principal NUMERIC(20,2) NOT NULL CHECK (principal > 0),
  outstanding_principal NUMERIC(20,2) NOT NULL CHECK (outstanding_principal >= 0),
  daily_rate NUMERIC(12,8) NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','repaid','defaulted','cancelled')),
  started_game_day BIGINT NOT NULL,
  due_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bank_deposits (
  id TEXT PRIMARY KEY,
  depositor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  principal_units BIGINT NOT NULL CHECK (principal_units > 0),
  accrued_interest_units BIGINT NOT NULL DEFAULT 0 CHECK (accrued_interest_units >= 0),
  rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0 AND rate_bps <= 5000),
  rate_rule_version TEXT NOT NULL,
  start_total_game_minute BIGINT NOT NULL CHECK (start_total_game_minute >= 0),
  maturity_total_game_minute BIGINT NOT NULL CHECK (maturity_total_game_minute > start_total_game_minute),
  early_withdrawal_allowed BOOLEAN NOT NULL DEFAULT FALSE,
  early_withdrawal_penalty_bps INTEGER NOT NULL DEFAULT 0 CHECK (early_withdrawal_penalty_bps BETWEEN 0 AND 10000),
  rules_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'MATURED', 'WITHDRAWN', 'ROLLED_OVER', 'DEFAULTED')),
  created_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  payout_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  deposit_protection_limit_units BIGINT NOT NULL DEFAULT 10000,
  deposit_protection_rule_version TEXT NOT NULL DEFAULT 'deposit-protection-v1',
  last_interest_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS deposit_protection_rules (
  id TEXT PRIMARY KEY,
  protection_limit_units BIGINT NOT NULL DEFAULT 0,
  rule_version TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS deposit_protection_claims (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deposit_id TEXT NOT NULL REFERENCES bank_deposits(id),
  depositor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  protection_limit_units BIGINT NOT NULL,
  insured_amount_units BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'PENDING',
  fiscal_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS owner_financial_summary (
  owner_economic_id BIGINT PRIMARY KEY REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL,
  liquid_credit_units BIGINT NOT NULL DEFAULT 0,
  escrowed_credit_units BIGINT NOT NULL DEFAULT 0,
  deposit_principal_units BIGINT NOT NULL DEFAULT 0,
  deposit_interest_units BIGINT NOT NULL DEFAULT 0,
  loan_liabilities_units BIGINT NOT NULL DEFAULT 0,
  tax_arrears_units BIGINT NOT NULL DEFAULT 0,
  net_financial_position_units BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS institution_financial_summary (
  institution_id TEXT PRIMARY KEY REFERENCES institutions(id),
  institution_kind TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  treasury_units BIGINT NOT NULL DEFAULT 0,
  operations_units BIGINT NOT NULL DEFAULT 0,
  reserve_units BIGINT NOT NULL DEFAULT 0,
  committed_spending_units BIGINT NOT NULL DEFAULT 0,
  debt_units BIGINT NOT NULL DEFAULT 0,
  tax_receivables_units BIGINT NOT NULL DEFAULT 0,
  distributable_surplus_units BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tax_daily_summary (
  game_day BIGINT PRIMARY KEY,
  assessed_units BIGINT NOT NULL DEFAULT 0,
  paid_units BIGINT NOT NULL DEFAULT 0,
  arrears_units BIGINT NOT NULL DEFAULT 0,
  waived_units BIGINT NOT NULL DEFAULT 0,
  obligation_count BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS bank_deposits_owner_status_idx ON bank_deposits(depositor_economic_id, status, maturity_total_game_minute);
CREATE INDEX IF NOT EXISTS bank_deposits_maturity_idx ON bank_deposits(status, maturity_total_game_minute);

CREATE TABLE IF NOT EXISTS bank_loans (
  id TEXT PRIMARY KEY,
  borrower_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  borrower_type TEXT NOT NULL CHECK (borrower_type IN ('human', 'city', 'corporation')),
  original_principal_units BIGINT NOT NULL CHECK (original_principal_units > 0),
  outstanding_principal_units BIGINT NOT NULL CHECK (outstanding_principal_units >= 0),
  accrued_interest_units BIGINT NOT NULL DEFAULT 0 CHECK (accrued_interest_units >= 0),
  rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0 AND rate_bps <= 5000),
  rate_rule_version TEXT NOT NULL,
  origination_total_game_minute BIGINT NOT NULL CHECK (origination_total_game_minute >= 0),
  installment_interval_days INTEGER NOT NULL DEFAULT 1 CHECK (installment_interval_days > 0),
  next_payment_game_day BIGINT,
  remaining_installments INTEGER NOT NULL DEFAULT 0 CHECK (remaining_installments >= 0),
  grace_period_days INTEGER NOT NULL DEFAULT 0 CHECK (grace_period_days >= 0),
  max_missed_payments INTEGER NOT NULL DEFAULT 3 CHECK (max_missed_payments >= 0),
  status TEXT NOT NULL DEFAULT 'CURRENT' CHECK (status IN ('CURRENT', 'GRACE', 'DELINQUENT', 'DEFAULTED', 'RESTRUCTURED', 'REPAID', 'WRITTEN_OFF')),
  origination_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  last_interest_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS bank_loans_borrower_status_idx ON bank_loans(borrower_economic_id, status);
CREATE INDEX IF NOT EXISTS bank_loans_payment_idx ON bank_loans(status, next_payment_game_day);

CREATE TABLE IF NOT EXISTS global_bank_rules (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version TEXT NOT NULL UNIQUE,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  minimum_liquidity_ratio NUMERIC(20,8) NOT NULL CHECK (minimum_liquidity_ratio >= 0),
  minimum_capital_ratio NUMERIC(20,8) NOT NULL CHECK (minimum_capital_ratio >= 0),
  maximum_single_borrower_exposure_units BIGINT NOT NULL CHECK (maximum_single_borrower_exposure_units > 0),
  maximum_total_lending_ratio NUMERIC(20,8) NOT NULL CHECK (maximum_total_lending_ratio >= 0),
  deposit_rate_bps INTEGER NOT NULL CHECK (deposit_rate_bps BETWEEN 0 AND 5000),
  loan_rate_bps INTEGER NOT NULL CHECK (loan_rate_bps BETWEEN 0 AND 5000),
  grace_period_days INTEGER NOT NULL CHECK (grace_period_days >= 0),
  default_threshold_days INTEGER NOT NULL CHECK (default_threshold_days >= grace_period_days),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS global_bank_rules_effective_range_uq
  ON global_bank_rules(effective_from_game_day, version);
INSERT INTO global_bank_rules (
  version, effective_from_game_day, minimum_liquidity_ratio, minimum_capital_ratio,
  maximum_single_borrower_exposure_units, maximum_total_lending_ratio,
  deposit_rate_bps, loan_rate_bps, grace_period_days, default_threshold_days
) VALUES ('global-bank-v2', 0, 0.20, 0.08, 100000000, 2.00, 10, 500, 2, 7)
ON CONFLICT (version) DO NOTHING;

CREATE TABLE IF NOT EXISTS bank_loan_payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id), transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE, payment_units BIGINT NOT NULL CHECK (payment_units > 0),
  interest_units BIGINT NOT NULL CHECK (interest_units >= 0), principal_units BIGINT NOT NULL CHECK (principal_units >= 0),
  game_day BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bank_settlement_journals (
  game_day BIGINT PRIMARY KEY,
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  loans_accrued BIGINT NOT NULL DEFAULT 0,
  deposits_accrued BIGINT NOT NULL DEFAULT 0,
  loan_payments BIGINT NOT NULL DEFAULT 0,
  deposit_payouts BIGINT NOT NULL DEFAULT 0,
  loan_payment_units BIGINT NOT NULL DEFAULT 0,
  deposit_payout_units BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL CHECK (status IN ('COMPLETED', 'LIQUIDITY_CONSTRAINED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tax_obligations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  taxpayer_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  beneficiary_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  tax_type TEXT NOT NULL CHECK (tax_type IN ('basic_levy', 'personal_income', 'corporate_income', 'market_transaction', 'property', 'building')),
  tax_base_units BIGINT NOT NULL CHECK (tax_base_units >= 0),
  rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0 AND rate_bps <= 10000),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  rule_version TEXT NOT NULL,
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE', 'PAID', 'PARTIAL', 'ARREARS', 'WAIVED')),
  payment_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
);
CREATE INDEX IF NOT EXISTS tax_obligations_payment_idx ON tax_obligations(status, game_day, taxpayer_economic_id);

CREATE TABLE IF NOT EXISTS global_bank_balance_sheet (
  game_day BIGINT PRIMARY KEY CHECK (game_day >= 0),
  reserve_units BIGINT NOT NULL CHECK (reserve_units >= 0),
  performing_loans_units BIGINT NOT NULL CHECK (performing_loans_units >= 0),
  impaired_loans_units BIGINT NOT NULL CHECK (impaired_loans_units >= 0),
  interest_receivable_units BIGINT NOT NULL CHECK (interest_receivable_units >= 0),
  deposit_principal_units BIGINT NOT NULL CHECK (deposit_principal_units >= 0),
  deposit_interest_payable_units BIGINT NOT NULL CHECK (deposit_interest_payable_units >= 0),
  withdrawals_payable_units BIGINT NOT NULL CHECK (withdrawals_payable_units >= 0),
  assets_units BIGINT NOT NULL, liabilities_units BIGINT NOT NULL, equity_units BIGINT NOT NULL,
  liquidity_ratio NUMERIC(20,8), capital_ratio NUMERIC(20,8),
  status TEXT NOT NULL CHECK (status IN ('healthy', 'illiquid', 'liquidity_stress', 'undercapitalized', 'insolvent', 'resolution')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS global_bank_resolution_state (
  id SMALLINT PRIMARY KEY CHECK (id = 1),
  status TEXT NOT NULL CHECK (status IN ('NORMAL','LIQUIDITY_STRESS','UNDERCAPITALIZED','INSOLVENT','RESOLUTION')),
  as_of_game_day BIGINT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS global_bank_resolution_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_day BIGINT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  action TEXT NOT NULL,
  amount_units BIGINT NOT NULL DEFAULT 0,
  economic_transaction_id BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS global_bank_balance_sheet_status_idx ON global_bank_balance_sheet (status, game_day DESC);
CREATE INDEX IF NOT EXISTS global_bank_loans_corporation_idx ON global_bank_loans(corporation_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS global_bank_settlement_journals (
  id UUID PRIMARY KEY,
  game_day BIGINT NOT NULL UNIQUE,
  loan_income NUMERIC(20,2) NOT NULL DEFAULT 0,
  operating_costs NUMERIC(20,2) NOT NULL DEFAULT 0,
  reserve_contribution NUMERIC(20,2) NOT NULL DEFAULT 0,
  interest_pool NUMERIC(20,2) NOT NULL DEFAULT 0,
  interest_paid NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS civic_rankings (
  id TEXT PRIMARY KEY,
  entity_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('city','corporation')),
  rank INTEGER NOT NULL,
  score NUMERIC(12,4) NOT NULL,
  tier TEXT NOT NULL,
  metrics_json JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_civic_rankings_type_rank ON civic_rankings(entity_type, rank);

CREATE TABLE IF NOT EXISTS communities (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  founder_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL DEFAULT 'active',
  description TEXT NOT NULL DEFAULT '',
  admission_policy TEXT NOT NULL DEFAULT 'open' CHECK (admission_policy IN ('open','application','approval','closed')),
  open_membership BOOLEAN NOT NULL DEFAULT TRUE,
  auto_join_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_members (
  community_id TEXT NOT NULL REFERENCES communities(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('founder','admin','member')),
  joined_game_day BIGINT NOT NULL,
  PRIMARY KEY (community_id, human_id)
);
CREATE INDEX IF NOT EXISTS community_members_human_idx ON community_members(human_id);

CREATE TABLE IF NOT EXISTS community_membership_requests (
  id TEXT PRIMARY KEY,
  community_id TEXT NOT NULL REFERENCES communities(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
  requested_game_day BIGINT NOT NULL,
  resolved_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS community_membership_requests_comm_idx ON community_membership_requests(community_id, status);
CREATE INDEX IF NOT EXISTS community_membership_requests_human_idx ON community_membership_requests(human_id, status);

CREATE TABLE IF NOT EXISTS proposals (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  decision_status TEXT NOT NULL DEFAULT 'scheduled' CHECK (decision_status IN ('scheduled','voting','passed','rejected','no_quorum','cancelled')),
  conflict_key TEXT,
  opens_at TIMESTAMPTZ NOT NULL,
  opens_game_day BIGINT,
  opens_game_minute INTEGER CHECK (opens_game_minute BETWEEN 0 AND 1439),
  closes_at TIMESTAMPTZ NOT NULL,
  rule_version_id TEXT,
  quorum NUMERIC(10,6) NOT NULL DEFAULT 0.25,
  approval_threshold NUMERIC(10,6) NOT NULL DEFAULT 0.5,
  implementation_delay_days INTEGER NOT NULL DEFAULT 0,
  outcome TEXT NOT NULL DEFAULT 'pending' CHECK (outcome IN ('pending','passed','rejected','no_quorum')),
  implementation_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  target_category TEXT,
  target_value_json JSONB,
  target_kind TEXT NOT NULL DEFAULT 'generic' CHECK (target_kind IN ('generic', 'building_catalog', 'research_project', 'finance_rule')),
  building_catalog_id TEXT REFERENCES building_catalog(id) ON DELETE RESTRICT,
  research_project_id TEXT,
  executed_at TIMESTAMPTZ,
  execution_status TEXT NOT NULL DEFAULT 'not_ready' CHECK (execution_status IN ('not_ready','ready','awaiting_funding','started','executed','skipped','expired_unfunded','blocked')),
  challenge_status TEXT NOT NULL DEFAULT 'none' CHECK (challenge_status IN ('none','pending','upheld','voided')),
  started_at TIMESTAMPTZ,
  started_game_day BIGINT,
  started_action_id TEXT,
  correlation_id TEXT,
  closes_game_day BIGINT,
  closes_game_minute INTEGER CHECK (closes_game_minute BETWEEN 0 AND 1439),
  implementation_game_day BIGINT,
  implementation_game_minute INTEGER CHECK (implementation_game_minute BETWEEN 0 AND 1439),
  expires_game_day BIGINT,
  expires_game_minute INTEGER DEFAULT 0 CHECK (expires_game_minute BETWEEN 0 AND 1439),
  created_by_human_id TEXT REFERENCES humans(id) ON DELETE SET NULL,
  submitted_game_day BIGINT NOT NULL DEFAULT 1,
  voting_start_day BIGINT NOT NULL DEFAULT 1,
  voting_duration_days INTEGER NOT NULL DEFAULT 1,
  voting_due_end_day BIGINT NOT NULL DEFAULT 1,
  resolved_game_day BIGINT,
  implementation_due_end_day BIGINT,
  executed_game_day BIGINT,
  funding_start_day BIGINT,
  funding_due_end_day BIGINT,
  funding_last_checked_day BIGINT,
  funding_block_reason TEXT,
  funding_requirements JSONB NOT NULL DEFAULT '{}'::jsonb,
  governance_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  action_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  proposal_schema_version INTEGER NOT NULL DEFAULT 1,
  action_handler_version INTEGER NOT NULL DEFAULT 1,
  snapshot_hash TEXT,
  eligible_voter_count BIGINT,
  eligibility_cutoff_game_day BIGINT,
  CONSTRAINT proposals_single_entity_target_check CHECK (num_nonnulls(building_catalog_id, research_project_id) <= 1)
);
CREATE UNIQUE INDEX IF NOT EXISTS proposals_institution_correlation_idx ON proposals(institution_id, correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS proposals_game_deadline_idx ON proposals(status, closes_game_day, closes_game_minute);
CREATE INDEX IF NOT EXISTS idx_proposals_institution_status ON proposals(institution_id, status);
CREATE INDEX IF NOT EXISTS proposals_building_catalog_target_idx ON proposals(building_catalog_id) WHERE building_catalog_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS proposals_research_project_target_idx ON proposals(research_project_id) WHERE research_project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS proposals_queued_expiry_idx ON proposals (execution_status, expires_game_day) WHERE execution_status = 'queued';
CREATE INDEX IF NOT EXISTS proposals_created_by_human_id_idx ON proposals(created_by_human_id);
CREATE INDEX IF NOT EXISTS proposals_funding_window_idx ON proposals(execution_status, funding_due_end_day) WHERE execution_status = 'awaiting_funding';
CREATE UNIQUE INDEX IF NOT EXISTS proposals_active_conflict_idx ON proposals(conflict_key) WHERE conflict_key IS NOT NULL AND decision_status IN ('scheduled','voting','passed');

CREATE TABLE IF NOT EXISTS proposal_actions (
  id TEXT PRIMARY KEY,
  proposal_id TEXT NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK (sequence > 0),
  action_type TEXT NOT NULL,
  handler_version INTEGER NOT NULL DEFAULT 1,
  payload_snapshot JSONB NOT NULL,
  execution_status TEXT NOT NULL DEFAULT 'pending',
  started_game_day BIGINT,
  completed_game_day BIGINT,
  result_json JSONB,
  correlation_id TEXT NOT NULL UNIQUE,
  UNIQUE (proposal_id, sequence)
);

CREATE TABLE IF NOT EXISTS proposal_action_requirements (
  id TEXT PRIMARY KEY,
  proposal_action_id TEXT NOT NULL REFERENCES proposal_actions(id) ON DELETE CASCADE,
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  required_units BIGINT NOT NULL CHECK (required_units > 0),
  source_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  source_account_type SMALLINT NOT NULL,
  requirement_kind TEXT NOT NULL DEFAULT 'funding',
  UNIQUE (proposal_action_id, asset_id)
);

CREATE TABLE IF NOT EXISTS proposal_challenge_authorities (
  institution_id TEXT NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  role_code TEXT NOT NULL CHECK (role_code IN ('constitutional_judge','judicial_delegate','ouc_court')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  granted_game_day BIGINT NOT NULL DEFAULT 1,
  PRIMARY KEY (institution_id, human_id, role_code)
);

CREATE TABLE IF NOT EXISTS proposal_vote_totals (
  proposal_id TEXT PRIMARY KEY REFERENCES proposals(id) ON DELETE CASCADE,
  voter_count BIGINT NOT NULL DEFAULT 0 CHECK (voter_count >= 0),
  support_count BIGINT NOT NULL DEFAULT 0 CHECK (support_count >= 0),
  oppose_count BIGINT NOT NULL DEFAULT 0 CHECK (oppose_count >= 0),
  abstain_count BIGINT NOT NULL DEFAULT 0 CHECK (abstain_count >= 0),
  support_weight NUMERIC(20,3) NOT NULL DEFAULT 0,
  oppose_weight NUMERIC(20,3) NOT NULL DEFAULT 0,
  abstain_weight NUMERIC(20,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ballots (
  proposal_id TEXT NOT NULL REFERENCES proposals(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  choice TEXT NOT NULL CHECK (choice IN ('support','oppose','abstain')),
  weight NUMERIC(10,3) NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (proposal_id, human_id)
);

CREATE TABLE IF NOT EXISTS governance_rules (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  value_json JSONB NOT NULL DEFAULT '{}',
  quorum_threshold NUMERIC(10,4) NOT NULL DEFAULT 0,
  approval_threshold NUMERIC(10,4) NOT NULL DEFAULT 0,
  voting_period_days INTEGER NOT NULL DEFAULT 3,
  implementation_delay_days INTEGER NOT NULL DEFAULT 0,
  effective_from_game_day BIGINT NOT NULL DEFAULT 1,
  effective_to_game_day BIGINT,
  version INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','superseded','repealed')),
  created_by TEXT NOT NULL REFERENCES humans(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (institution_id, category, version)
);
CREATE INDEX IF NOT EXISTS idx_gov_rules_inst_cat ON governance_rules(institution_id, category, status);
CREATE UNIQUE INDEX IF NOT EXISTS governance_rules_one_active_category ON governance_rules(institution_id, category) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS constitutional_rules (
  rule_key TEXT PRIMARY KEY,
  statute_title TEXT NOT NULL,
  description TEXT NOT NULL,
  rule_value_json JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 9. Technology & R&D
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS technology_catalog (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('PRODUCTION','EFFICIENCY','CONSTRUCTION','ENERGY','MAINTENANCE','RESEARCH','SERVICES','LOGISTICS')),
  description TEXT NOT NULL,
  patentable BOOLEAN NOT NULL DEFAULT FALSE,
  patent_exclusivity_days INTEGER NOT NULL DEFAULT 0 CHECK (patent_exclusivity_days >= 0),
  research_credit_cost_units BIGINT NOT NULL CHECK (research_credit_cost_units > 0),
  research_points_required BIGINT NOT NULL CHECK (research_points_required > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED','RETIRED')),
  definition_version INTEGER NOT NULL DEFAULT 1 CHECK (definition_version > 0),
  effective_from_game_day BIGINT NOT NULL DEFAULT 0 CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  CHECK (patentable OR patent_exclusivity_days = 0),
  UNIQUE (code, effective_from_game_day),
  UNIQUE (code, definition_version)
);
CREATE INDEX IF NOT EXISTS technology_catalog_effective_idx ON technology_catalog (code, effective_from_game_day DESC) WHERE status IN ('ACTIVE', 'SUPERSEDED');

CREATE TABLE IF NOT EXISTS corporation_technology_specializations (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  specialization_code TEXT NOT NULL CHECK (specialization_code IN ('INDUSTRY','ENERGY','COMPUTE','AGRICULTURE','CONSTRUCTION','SERVICES')),
  efficiency_bonus_bps INTEGER NOT NULL DEFAULT 1000 CHECK (efficiency_bonus_bps BETWEEN 0 AND 1500),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUPERSEDED','REVOKED')),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, effective_from_game_day),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS corporation_technology_specialization_active_idx ON corporation_technology_specializations (corporation_economic_id) WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;

CREATE TABLE IF NOT EXISTS technology_prerequisites (
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id) ON DELETE CASCADE,
  requires_technology_id TEXT NOT NULL REFERENCES technology_catalog(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (technology_id, requires_technology_id),
  CHECK (technology_id <> requires_technology_id)
);
CREATE INDEX IF NOT EXISTS technology_prerequisites_requires_idx ON technology_prerequisites (requires_technology_id, technology_id);

CREATE TABLE IF NOT EXISTS technology_effects (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id) ON DELETE CASCADE,
  effect_type TEXT NOT NULL CHECK (effect_type IN ('PRODUCTION_OUTPUT','RESOURCE_INPUT','CONSTRUCTION_TIME','CONSTRUCTION_RESOURCE_COST','BUILDING_WEAR','REPAIR_EFFICIENCY','RESEARCH_CAPACITY','SERVICE_CAPACITY','ENERGY_INPUT')),
  target_type TEXT NOT NULL CHECK (target_type IN ('ALL_BUILDINGS','ASSET','BUILDING','SERVICE','RESEARCH')),
  target_key TEXT NOT NULL,
  modifier_family TEXT NOT NULL,
  modifier_bps INTEGER NOT NULL CHECK (modifier_bps BETWEEN -100000 AND 100000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (technology_id, effect_type, target_type, target_key)
);
CREATE INDEX IF NOT EXISTS technology_effects_target_idx ON technology_effects (effect_type, target_type, target_key, technology_id);

CREATE TABLE IF NOT EXISTS technology_modifier_rules (
  family_code TEXT PRIMARY KEY,
  effect_type TEXT NOT NULL UNIQUE,
  stacking_mode TEXT NOT NULL DEFAULT 'ADDITIVE_BPS' CHECK (stacking_mode = 'ADDITIVE_BPS'),
  minimum_bps INTEGER NOT NULL,
  maximum_bps INTEGER NOT NULL,
  effective_from_game_day BIGINT NOT NULL DEFAULT 0,
  effective_to_game_day BIGINT,
  definition_version INTEGER NOT NULL DEFAULT 1,
  CHECK (minimum_bps <= maximum_bps),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS technology_effects_family_idx ON technology_effects (modifier_family, target_type, target_key, technology_id);

CREATE TABLE IF NOT EXISTS corporation_research_projects (
  id TEXT PRIMARY KEY,
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  target_type TEXT NOT NULL CHECK (target_type IN ('TECHNOLOGY','BUILDING_BLUEPRINT')),
  target_id TEXT NOT NULL,
  definition_version TEXT NOT NULL,
  definition_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  specialization_bonus_bps INTEGER NOT NULL DEFAULT 0 CHECK (specialization_bonus_bps BETWEEN 0 AND 1500),
  required_research_points BIGINT NOT NULL CHECK (required_research_points > 0),
  progress_research_points BIGINT NOT NULL DEFAULT 0 CHECK (progress_research_points >= 0),
  credit_cost_units BIGINT NOT NULL CHECK (credit_cost_units >= 0),
  priority INTEGER NOT NULL DEFAULT 100 CHECK (priority BETWEEN 0 AND 1000),
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','ACTIVE','COMPLETED','CANCELLED')),
  started_game_day BIGINT,
  completed_game_day BIGINT,
  funding_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (progress_research_points <= required_research_points),
  CHECK (completed_game_day IS NULL OR started_game_day IS NULL OR completed_game_day >= started_game_day)
  ,CHECK (status <> 'ACTIVE' OR funding_transaction_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS corporation_research_projects_queue_idx ON corporation_research_projects (corporation_economic_id, status, priority DESC, created_at, id);
CREATE UNIQUE INDEX IF NOT EXISTS corporation_research_projects_active_target_idx ON corporation_research_projects (corporation_economic_id, target_type, target_id) WHERE status IN ('QUEUED','ACTIVE','COMPLETED');
CREATE UNIQUE INDEX IF NOT EXISTS corporation_research_one_active_idx ON corporation_research_projects (corporation_economic_id) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS corporation_research_funding_idx ON corporation_research_projects (funding_transaction_id) WHERE funding_transaction_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS technology_patents (
  id TEXT PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  granted_game_day BIGINT NOT NULL CHECK (granted_game_day >= 0),
  exclusive_through_game_day BIGINT NOT NULL CHECK (exclusive_through_game_day >= granted_game_day),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXPIRED', 'REVOKED')),
  granting_project_id TEXT NOT NULL REFERENCES corporation_research_projects(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS technology_patents_one_active_idx ON technology_patents (technology_id) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS technology_patents_owner_idx ON technology_patents (owner_economic_id, status);

CREATE TABLE IF NOT EXISTS technology_public_domain (
  technology_id TEXT PRIMARY KEY REFERENCES technology_catalog(id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  source_patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS technology_public_domain_effective_idx ON technology_public_domain (effective_from_game_day, technology_id);

CREATE TABLE IF NOT EXISTS technology_license_contracts (
  id TEXT PRIMARY KEY,
  patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  licensor_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  licensee_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  upfront_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (upfront_fee_units >= 0),
  daily_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (daily_fee_units >= 0),
  definition_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  patent_terms_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  upfront_transaction_id BIGINT,
  last_daily_transaction_id BIGINT,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'EXPIRED', 'TERMINATED')),
  paid_through_game_day BIGINT NOT NULL,
  suspended_game_day BIGINT,
  suspension_reason TEXT,
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (licensee_economic_id <> licensor_economic_id),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  CHECK (paid_through_game_day < effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS technology_license_contracts_licensee_idx ON technology_license_contracts (licensee_economic_id, status, effective_from_game_day, effective_to_game_day);
CREATE INDEX IF NOT EXISTS technology_license_contracts_patent_idx ON technology_license_contracts (patent_id, status);

CREATE TABLE IF NOT EXISTS technology_patent_ownership_transfers (
  id BIGSERIAL PRIMARY KEY,
  patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  from_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  to_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS technology_patent_ownership_transfer_once_idx ON technology_patent_ownership_transfers (patent_id, from_owner_economic_id, to_owner_economic_id);

CREATE TABLE IF NOT EXISTS technology_license_payments (
  id BIGSERIAL PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES technology_license_contracts(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  transaction_id BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (contract_id, game_day)
);
CREATE INDEX IF NOT EXISTS technology_license_payments_contract_idx ON technology_license_payments (contract_id, game_day);

CREATE TABLE IF NOT EXISTS corporation_technology_access (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id),
  access_source TEXT NOT NULL CHECK (access_source IN ('RESEARCHED','LICENSED','GRANTED')),
  source_id TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','EXPIRED','REVOKED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, technology_id, access_source, source_id),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS corporation_technology_access_lookup_idx ON corporation_technology_access (corporation_economic_id, technology_id, effective_from_game_day, effective_to_game_day) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS corporation_technology_access_expiry_idx ON corporation_technology_access (effective_to_game_day) WHERE status = 'ACTIVE' AND effective_to_game_day IS NOT NULL;

CREATE TABLE IF NOT EXISTS corporation_technology_modifier_cache (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  production_output_bps INTEGER NOT NULL DEFAULT 0,
  material_input_bps INTEGER NOT NULL DEFAULT 0,
  energy_input_bps INTEGER NOT NULL DEFAULT 0,
  construction_time_bps INTEGER NOT NULL DEFAULT 0,
  construction_cost_bps INTEGER NOT NULL DEFAULT 0,
  wear_bps INTEGER NOT NULL DEFAULT 0,
  repair_efficiency_bps INTEGER NOT NULL DEFAULT 0,
  research_capacity_bps INTEGER NOT NULL DEFAULT 0,
  service_capacity_bps INTEGER NOT NULL DEFAULT 0,
  scoped_modifiers JSONB NOT NULL DEFAULT '{}'::JSONB,
  technology_source_breakdown JSONB NOT NULL DEFAULT '[]'::JSONB,
  source_count INTEGER NOT NULL DEFAULT 0 CHECK (source_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, game_day)
);
CREATE INDEX IF NOT EXISTS corporation_technology_modifier_cache_day_idx ON corporation_technology_modifier_cache (game_day, corporation_economic_id);

CREATE TABLE IF NOT EXISTS corporation_technology_modifier_invalidations (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  effective_game_day BIGINT NOT NULL CHECK (effective_game_day >= 0),
  reason_code TEXT NOT NULL,
  source_id TEXT NOT NULL,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, effective_game_day, reason_code, source_id)
);
CREATE INDEX IF NOT EXISTS corporation_technology_modifier_invalidations_pending_idx ON corporation_technology_modifier_invalidations (effective_game_day, corporation_economic_id) WHERE resolved_at IS NULL;

ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS research_capacity_units_per_day BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_plans ADD COLUMN IF NOT EXISTS research_capacity_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_plans ADD COLUMN IF NOT EXISTS research_points_generated BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS corporation_research_capacity_daily (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  base_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (base_capacity_units >= 0),
  technology_modifier_bps INTEGER NOT NULL DEFAULT 0,
  effective_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (effective_capacity_units >= 0),
  source_building_count INTEGER NOT NULL DEFAULT 0 CHECK (source_building_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, game_day)
);
CREATE INDEX IF NOT EXISTS corporation_research_capacity_day_idx ON corporation_research_capacity_daily (game_day, corporation_economic_id);

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
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_corp_tech_pool UNIQUE (corporation_id, technology_key)
);
CREATE INDEX IF NOT EXISTS corporate_research_corp_idx ON corporate_research_pools(corporation_id, status);
CREATE INDEX IF NOT EXISTS idx_corp_research_corp_tech ON corporate_research_pools(corporation_id, technology_key);

-- -----------------------------------------------------------------------------
-- 10. Contracts, Supply & Arbitration
-- -----------------------------------------------------------------------------

/* RETIRED: negotiated_contracts, contract_disputes, supply_contracts,
   contract_escrow_vaults, and contract_delivery_ticks are removed by
   migration 121. Market futures use the V2 derivative obligations model. */
/*
CREATE TABLE IF NOT EXISTS negotiated_contracts (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('employment','intellectual_service','capacity','strategic')),
  proposer_id TEXT NOT NULL REFERENCES humans(id),
  counterparty_id TEXT NOT NULL REFERENCES humans(id),
  title TEXT NOT NULL,
  terms_text TEXT NOT NULL DEFAULT '',
  amount NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','accepted','cancelled','completed')),
  starts_game_day BIGINT NOT NULL,
  ends_game_day BIGINT NOT NULL,
  accepted_game_day BIGINT,
  correlation_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (proposer_id <> counterparty_id)
);
CREATE INDEX IF NOT EXISTS negotiated_contracts_party_idx ON negotiated_contracts(proposer_id, counterparty_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS negotiated_contracts_correlation_idx ON negotiated_contracts(proposer_id, correlation_id) WHERE correlation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS contract_disputes (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES negotiated_contracts(id),
  claimant_id TEXT NOT NULL REFERENCES humans(id),
  respondent_id TEXT NOT NULL REFERENCES humans(id),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','rejected')),
  outcome TEXT CHECK (outcome IN ('uphold','void')),
  resolved_by TEXT REFERENCES humans(id),
  resolved_game_day BIGINT,
  resolution TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS open_contract_dispute_idx ON contract_disputes(contract_id) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_contract_disputes_parties ON contract_disputes(claimant_id, respondent_id, status);

CREATE TABLE IF NOT EXISTS supply_contracts (
  id UUID PRIMARY KEY,
  buyer_id TEXT NOT NULL REFERENCES humans(id),
  supplier_id TEXT NOT NULL REFERENCES humans(id),
  resource TEXT NOT NULL CHECK (resource IN ('material','components','energy','compute','food')),
  quantity_per_tick NUMERIC(20,6) NOT NULL CHECK (quantity_per_tick > 0),
  price_per_unit NUMERIC(20,2) NOT NULL CHECK (price_per_unit > 0),
  interval_ticks INTEGER NOT NULL DEFAULT 1 CHECK (interval_ticks >= 1),
  total_ticks INTEGER NOT NULL CHECK (total_ticks > 0),
  completed_ticks INTEGER NOT NULL DEFAULT 0 CHECK (completed_ticks >= 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','fulfilled','defaulted','cancelled')),
  escrow_required BOOLEAN NOT NULL DEFAULT TRUE,
  created_game_day BIGINT NOT NULL,
  last_delivery_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_supply_contracts_buyer ON supply_contracts(buyer_id, status);
CREATE INDEX IF NOT EXISTS idx_supply_contracts_supplier ON supply_contracts(supplier_id, status);

CREATE TABLE IF NOT EXISTS contract_escrow_vaults (
  contract_id UUID PRIMARY KEY REFERENCES supply_contracts(id) ON DELETE CASCADE,
  locked_credits NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (locked_credits >= 0),
  locked_resources NUMERIC(20,6) NOT NULL DEFAULT 0 CHECK (locked_resources >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contract_delivery_ticks (
  id UUID PRIMARY KEY,
  contract_id UUID NOT NULL REFERENCES supply_contracts(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  quantity_delivered NUMERIC(20,6) NOT NULL,
  credits_transferred NUMERIC(20,2) NOT NULL,
  success BOOLEAN NOT NULL DEFAULT TRUE,
  failure_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_delivery_ticks_contract ON contract_delivery_ticks(contract_id, game_day DESC);
*/

-- -----------------------------------------------------------------------------
-- 11. Communications & AI Advisory
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS comm_channels (
  id TEXT PRIMARY KEY,
  scope TEXT NOT NULL CHECK (scope IN ('global','city','corporation','community','direct')),
  scope_id TEXT,
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_comm_channels_scope ON comm_channels(scope, scope_id);

CREATE TABLE IF NOT EXISTS comm_direct_conversations (
  channel_id TEXT PRIMARY KEY REFERENCES comm_channels(id) ON DELETE CASCADE,
  participant_low_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  participant_high_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (participant_low_id <> participant_high_id),
  CHECK (participant_low_id < participant_high_id),
  UNIQUE (participant_low_id, participant_high_id)
);
CREATE INDEX IF NOT EXISTS comm_direct_low_idx ON comm_direct_conversations(participant_low_id);
CREATE INDEX IF NOT EXISTS comm_direct_high_idx ON comm_direct_conversations(participant_high_id);

CREATE TABLE IF NOT EXISTS comm_messages (
  id UUID PRIMARY KEY,
  channel_id TEXT NOT NULL REFERENCES comm_channels(id) ON DELETE CASCADE,
  sender_human_id TEXT NOT NULL REFERENCES humans(id),
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_comm_messages_channel ON comm_messages(channel_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ai_assistants (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES humans(id),
  tier TEXT NOT NULL CHECK (tier IN ('basic','advanced')),
  policy TEXT NOT NULL DEFAULT 'recommend',
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ai_assistants_owner_idx ON ai_assistants(owner_id, enabled);

CREATE TABLE IF NOT EXISTS ai_recommendation_feedback (
  id UUID PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  recommendation_type TEXT NOT NULL,
  recommendation_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('accepted','dismissed','ignored')),
  feedback_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ai_rec_feedback_human ON ai_recommendation_feedback(human_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 12. System, Side-Effects & Observability
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ownership_events (
  id TEXT PRIMARY KEY,
  asset_type TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  from_owner_id TEXT,
  to_owner_id TEXT NOT NULL,
  quantity NUMERIC(20,6) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  reason_type TEXT NOT NULL,
  reason_id TEXT,
  game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ownership_events_asset_idx ON ownership_events(asset_type, asset_id, game_day DESC);
CREATE INDEX IF NOT EXISTS ownership_events_owner_idx ON ownership_events(to_owner_id, game_day DESC);

CREATE TABLE IF NOT EXISTS event_outbox (
  id UUID PRIMARY KEY,
  event_key TEXT NOT NULL UNIQUE,
  topic TEXT NOT NULL,
  aggregate_type TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  locked_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS event_outbox_pending_idx ON event_outbox(available_at, created_at) WHERE processed_at IS NULL;
CREATE INDEX IF NOT EXISTS event_outbox_aggregate_idx ON event_outbox(aggregate_type, aggregate_id, created_at);

CREATE TABLE IF NOT EXISTS scheduler_tick_logs (
  id UUID PRIMARY KEY,
  game_day BIGINT NOT NULL,
  engine TEXT NOT NULL,
  status TEXT NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  details_json JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_scheduler_tick_logs_day ON scheduler_tick_logs(game_day DESC);

CREATE TABLE IF NOT EXISTS scheduler_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scheduled_time BIGINT NOT NULL,
  worker_instance_id TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ,
  status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'partial', 'busy', 'failed')),
  game_day BIGINT,
  game_minute INTEGER,
  settlement_watermark_before BIGINT,
  settlement_watermark_after BIGINT,
  backlog_before BIGINT,
  backlog_after BIGINT,
  settlement_days_processed INTEGER NOT NULL DEFAULT 0,
  actions_processed INTEGER NOT NULL DEFAULT 0,
  market_batches_processed INTEGER NOT NULL DEFAULT 0,
  outbox_events_delivered INTEGER NOT NULL DEFAULT 0,
  error_stage TEXT,
  error_message TEXT
);
CREATE INDEX IF NOT EXISTS scheduler_runs_started_idx ON scheduler_runs(started_at DESC);
CREATE INDEX IF NOT EXISTS scheduler_runs_status_idx ON scheduler_runs(status, started_at DESC);

-- Durable daily economic settlement. The live database receives the matching
-- forward migrations; these definitions keep a fresh schema in sync.
CREATE TABLE IF NOT EXISTS daily_settlement_runs (
  game_day BIGINT PRIMARY KEY CHECK (game_day >= 1),
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'baseline', 'paused')),
  current_phase TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  shard_count INTEGER NOT NULL DEFAULT 1 CHECK (shard_count BETWEEN 1 AND 64),
  lease_owner TEXT,
  lease_heartbeat_at TIMESTAMPTZ,
  rules_version TEXT NOT NULL DEFAULT 'daily-settlement-v1',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS daily_settlement_runs_status_day_idx ON daily_settlement_runs(status, game_day);

CREATE TABLE IF NOT EXISTS daily_settlement_control (
  id TEXT PRIMARY KEY DEFAULT 'WORLD' CHECK (id = 'WORLD'),
  status TEXT NOT NULL CHECK (status IN ('awaiting_baseline', 'active', 'paused')) DEFAULT 'awaiting_baseline',
  activated_at TIMESTAMPTZ,
  activated_by TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO daily_settlement_control (id, status) VALUES ('WORLD', 'awaiting_baseline') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS daily_settlement_phase_runs (
  game_day BIGINT NOT NULL REFERENCES daily_settlement_runs(game_day) ON DELETE CASCADE,
  phase TEXT NOT NULL,
  shard TEXT NOT NULL DEFAULT 'all',
  status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  attempt_count INTEGER NOT NULL DEFAULT 0,
  rows_processed BIGINT NOT NULL DEFAULT 0,
  lease_owner TEXT,
  lease_heartbeat_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  PRIMARY KEY (game_day, phase, shard)
);
CREATE INDEX IF NOT EXISTS daily_settlement_phase_runs_lease_idx
  ON daily_settlement_phase_runs(status, lease_heartbeat_at);

CREATE TABLE IF NOT EXISTS entity_end_of_day_snapshots (
  owner_id TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  owner_kind TEXT NOT NULL,
  credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  resources JSONB NOT NULL DEFAULT '{}'::jsonb,
  cumulative_metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
  rules_version TEXT NOT NULL DEFAULT 'daily-settlement-v1',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, game_day)
);
CREATE INDEX IF NOT EXISTS entity_eod_snapshot_day_idx ON entity_end_of_day_snapshots(game_day DESC, owner_kind);

CREATE TABLE IF NOT EXISTS scheduled_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id TEXT,
  action_type TEXT NOT NULL,
  due_game_day BIGINT NOT NULL CHECK (due_game_day >= 1),
  due_game_minute INTEGER NOT NULL DEFAULT 0 CHECK (due_game_minute BETWEEN 0 AND 1439),
  due_end_game_day BIGINT NOT NULL DEFAULT 1,
  priority INTEGER NOT NULL DEFAULT 100,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  correlation_id TEXT NOT NULL UNIQUE,
  claimed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS scheduled_actions_due_idx ON scheduled_actions(status, due_game_day, due_game_minute);
CREATE INDEX IF NOT EXISTS scheduled_actions_end_of_day_idx ON scheduled_actions(status, due_end_game_day, priority, created_at);
ALTER TABLE scheduled_actions ADD COLUMN IF NOT EXISTS lease_owner TEXT;
ALTER TABLE scheduled_actions ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ;
ALTER TABLE scheduled_actions ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS scheduled_actions_lease_idx ON scheduled_actions(status, lease_expires_at);
ALTER TABLE market_prices ADD COLUMN IF NOT EXISTS last_market_batch_id BIGINT;

CREATE TABLE IF NOT EXISTS market_batch_runs (
  batch_id BIGINT NOT NULL,
  product TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed')),
  lease_owner TEXT,
  lease_expires_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  orders_processed BIGINT NOT NULL DEFAULT 0,
  trades_created BIGINT NOT NULL DEFAULT 0,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (batch_id, product)
);
CREATE INDEX IF NOT EXISTS market_batch_runs_status_idx ON market_batch_runs(status, batch_id);

CREATE TABLE IF NOT EXISTS market_batches (
  id BIGINT PRIMARY KEY,
  start_total_game_minute BIGINT NOT NULL,
  end_total_game_minute BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'clearing', 'completed', 'failed')),
  rules_version TEXT NOT NULL DEFAULT 'market-v2',
  rules_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  CHECK (start_total_game_minute >= 0 AND end_total_game_minute > start_total_game_minute)
);
CREATE TABLE IF NOT EXISTS market_batch_instruments (
  batch_id BIGINT NOT NULL REFERENCES market_batches(id),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'clearing', 'completed', 'failed')),
  lease_owner TEXT, lease_expires_at TIMESTAMPTZ,
  eligible_order_count BIGINT NOT NULL DEFAULT 0, fill_count BIGINT NOT NULL DEFAULT 0, volume_units BIGINT NOT NULL DEFAULT 0,
  previous_price_units BIGINT, clearing_price_units BIGINT, economic_transaction_id BIGINT,
  started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, error_message TEXT,
  PRIMARY KEY (batch_id, instrument_id)
);
CREATE INDEX IF NOT EXISTS market_batches_status_idx ON market_batches(status, id);
CREATE INDEX IF NOT EXISTS market_batch_instruments_lease_idx ON market_batch_instruments(status, lease_expires_at);

CREATE OR REPLACE FUNCTION earth_guard_market_order_rules()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.rules_version IS DISTINCT FROM NEW.rules_version
     OR OLD.buyer_fee_bps IS DISTINCT FROM NEW.buyer_fee_bps
     OR OLD.seller_fee_bps IS DISTINCT FROM NEW.seller_fee_bps
     OR OLD.rules_snapshot IS DISTINCT FROM NEW.rules_snapshot THEN
    RAISE EXCEPTION 'market order rules are immutable after acceptance';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS market_orders_rules_immutable ON market_orders;
CREATE TRIGGER market_orders_rules_immutable
BEFORE UPDATE OF rules_version, buyer_fee_bps, seller_fee_bps, rules_snapshot ON market_orders
FOR EACH ROW EXECUTE FUNCTION earth_guard_market_order_rules();

CREATE OR REPLACE FUNCTION earth_guard_market_batch_rules()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.rules_version IS DISTINCT FROM NEW.rules_version
     OR OLD.rules_snapshot IS DISTINCT FROM NEW.rules_snapshot THEN
    RAISE EXCEPTION 'market batch rules are immutable after creation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS market_batches_rules_immutable ON market_batches;
CREATE TRIGGER market_batches_rules_immutable
BEFORE UPDATE OF rules_version, rules_snapshot ON market_batches
FOR EACH ROW EXECUTE FUNCTION earth_guard_market_batch_rules();

CREATE TABLE IF NOT EXISTS market_fills (
  id UUID PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES market_batches(id),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  buy_order_id UUID NOT NULL REFERENCES market_orders(id),
  sell_order_id UUID NOT NULL REFERENCES market_orders(id),
  quantity_units BIGINT NOT NULL CHECK (quantity_units > 0),
  price_units BIGINT NOT NULL CHECK (price_units > 0),
  quote_units BIGINT NOT NULL CHECK (quote_units >= 0),
  fee_units BIGINT NOT NULL DEFAULT 0 CHECK (fee_units >= 0),
  buyer_economic_id BIGINT,
  seller_economic_id BIGINT,
  gross_quote_units BIGINT,
  buyer_fee_units BIGINT NOT NULL DEFAULT 0,
  seller_fee_units BIGINT NOT NULL DEFAULT 0,
  economic_transaction_id BIGINT,
  sequence_no BIGINT,
  game_day BIGINT,
  game_minute INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (batch_id, buy_order_id, sell_order_id)
);
CREATE INDEX IF NOT EXISTS market_fills_instrument_idx ON market_fills(instrument_id, batch_id);
CREATE INDEX IF NOT EXISTS market_fills_transaction_idx ON market_fills(economic_transaction_id);
CREATE INDEX IF NOT EXISTS market_fills_buyer_idx ON market_fills(buyer_economic_id, game_day);
CREATE INDEX IF NOT EXISTS market_fills_seller_idx ON market_fills(seller_economic_id, game_day);

CREATE TABLE IF NOT EXISTS market_instrument_state (
  instrument_id TEXT PRIMARY KEY REFERENCES market_instruments(id),
  last_completed_batch_id BIGINT,
  last_clearing_price_units BIGINT,
  best_bid_units BIGINT,
  best_ask_units BIGINT,
  open_buy_units BIGINT NOT NULL DEFAULT 0,
  open_sell_units BIGINT NOT NULL DEFAULT 0,
  rolling_volume_units BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO market_instrument_state (instrument_id, last_clearing_price_units)
SELECT i.id, p.price_units
  FROM market_instruments i
  JOIN market_prices p ON p.product = lower(regexp_replace(i.symbol, '^SPOT-', ''))
 WHERE i.instrument_type = 'SPOT'
ON CONFLICT (instrument_id) DO UPDATE
  SET last_clearing_price_units = COALESCE(market_instrument_state.last_clearing_price_units, EXCLUDED.last_clearing_price_units);
CREATE INDEX IF NOT EXISTS market_instrument_state_updated_idx ON market_instrument_state(updated_at);

CREATE TABLE IF NOT EXISTS market_candles (
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  interval_kind TEXT NOT NULL CHECK (interval_kind IN ('hourly', 'daily')),
  period_id BIGINT NOT NULL,
  open_price_units BIGINT NOT NULL CHECK (open_price_units > 0),
  high_price_units BIGINT NOT NULL CHECK (high_price_units > 0),
  low_price_units BIGINT NOT NULL CHECK (low_price_units > 0),
  close_price_units BIGINT NOT NULL CHECK (close_price_units > 0),
  volume_units BIGINT NOT NULL CHECK (volume_units >= 0),
  fill_count BIGINT NOT NULL CHECK (fill_count >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (instrument_id, interval_kind, period_id)
);
CREATE INDEX IF NOT EXISTS market_candles_lookup_idx ON market_candles(instrument_id, interval_kind, period_id DESC);

CREATE TABLE IF NOT EXISTS market_delivery_obligations (
  fill_id UUID PRIMARY KEY REFERENCES market_fills(id),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  batch_id BIGINT NOT NULL REFERENCES market_batches(id),
  buyer_order_id UUID NOT NULL REFERENCES market_orders(id),
  seller_order_id UUID NOT NULL REFERENCES market_orders(id),
  buyer_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  seller_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  quantity_units BIGINT NOT NULL CHECK (quantity_units > 0),
  agreed_price_units BIGINT NOT NULL CHECK (agreed_price_units > 0),
  expiry_total_game_minute BIGINT NOT NULL CHECK (expiry_total_game_minute > 0),
  buyer_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  seller_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'delivered', 'defaulted', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  settled_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS market_delivery_obligations_expiry_idx ON market_delivery_obligations(status, expiry_total_game_minute);
CREATE INDEX IF NOT EXISTS market_delivery_obligations_instrument_idx ON market_delivery_obligations(instrument_id, status, expiry_total_game_minute);

CREATE TABLE IF NOT EXISTS derivative_obligations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  originating_fill_id UUID NOT NULL REFERENCES market_fills(id),
  long_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  short_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  quantity_units BIGINT NOT NULL CHECK (quantity_units > 0),
  delivery_price_units BIGINT NOT NULL CHECK (delivery_price_units > 0),
  long_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  short_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  expiry_total_game_minute BIGINT NOT NULL CHECK (expiry_total_game_minute > 0),
  expiry_batch_id BIGINT NOT NULL CHECK (expiry_batch_id >= 0),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'settling', 'settled', 'cancelled')),
  settlement_transaction_id BIGINT REFERENCES economic_transactions(id),
  created_game_day BIGINT NOT NULL,
  created_game_minute INTEGER NOT NULL CHECK (created_game_minute BETWEEN 0 AND 1439),
  settled_game_day BIGINT,
  settled_game_minute INTEGER CHECK (settled_game_minute BETWEEN 0 AND 1439),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (originating_fill_id)
);
CREATE INDEX IF NOT EXISTS derivative_obligations_expiry_idx ON derivative_obligations(status, expiry_total_game_minute);
CREATE INDEX IF NOT EXISTS derivative_obligations_owner_idx ON derivative_obligations(long_owner_economic_id, short_owner_economic_id, status);

CREATE TABLE IF NOT EXISTS settlement_anomalies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_day BIGINT,
  severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'error', 'critical')),
  anomaly_type TEXT NOT NULL,
  owner_id TEXT,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS settlement_anomalies_open_idx ON settlement_anomalies(severity, created_at DESC) WHERE resolved_at IS NULL;

-- ----------------------------------------------------------------------------
-- Reconciled late-schema extensions (migrations 088, 092, 097, 107, 157-180)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION earth_building_corporation_economic_id(p_building_id TEXT)
RETURNS BIGINT LANGUAGE SQL STABLE AS $$
  SELECT CASE WHEN b.ownership_class = 'private' THEN COALESCE(corporation.economic_id, owner.economic_id) ELSE owner.economic_id END
  FROM buildings b
  JOIN owner_registry owner ON owner.id = COALESCE(b.owner_id, b.city_id)
  LEFT JOIN memberships membership ON membership.human_id = b.owner_id AND b.ownership_class = 'private'
  LEFT JOIN owner_registry corporation ON corporation.id = membership.corporation_id
  WHERE b.id = p_building_id;
$$;

CREATE TABLE IF NOT EXISTS app_error_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  human_id TEXT REFERENCES humans(id) ON DELETE SET NULL, source TEXT NOT NULL,
  endpoint TEXT, status_code INTEGER, error_code TEXT, error_message TEXT NOT NULL,
  stack_trace TEXT, context_data JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS building_catalog (
  id TEXT PRIMARY KEY, building_type TEXT NOT NULL, name TEXT NOT NULL,
  tier INTEGER NOT NULL DEFAULT 1, prev_catalog_id TEXT, next_catalog_id TEXT,
  category TEXT NOT NULL, ownership_class TEXT NOT NULL, slot_footprint INTEGER NOT NULL DEFAULT 1,
  cost_credits NUMERIC(18,6) DEFAULT 0, cost_energy NUMERIC(18,6) DEFAULT 0,
  cost_food NUMERIC(18,6) DEFAULT 0, cost_materials NUMERIC(18,6) DEFAULT 0,
  cost_components NUMERIC(18,6) DEFAULT 0, cost_compute NUMERIC(18,6) DEFAULT 0,
  output_credits NUMERIC(18,6) DEFAULT 0, output_energy NUMERIC(18,6) DEFAULT 0,
  output_food NUMERIC(18,6) DEFAULT 0, output_materials NUMERIC(18,6) DEFAULT 0,
  output_components NUMERIC(18,6) DEFAULT 0, output_compute NUMERIC(18,6) DEFAULT 0,
  upkeep_credits NUMERIC(18,6) DEFAULT 0, upkeep_energy NUMERIC(18,6) DEFAULT 0,
  upkeep_food NUMERIC(18,6) DEFAULT 0, upkeep_materials NUMERIC(18,6) DEFAULT 0,
  upkeep_components NUMERIC(18,6) DEFAULT 0, upkeep_compute NUMERIC(18,6) DEFAULT 0,
  operating_credits NUMERIC(18,6) DEFAULT 0, operating_energy NUMERIC(18,6) DEFAULT 0,
  operating_food NUMERIC(18,6) DEFAULT 0, operating_materials NUMERIC(18,6) DEFAULT 0,
  operating_components NUMERIC(18,6) DEFAULT 0, operating_compute NUMERIC(18,6) DEFAULT 0,
  unlocked_perks TEXT[] DEFAULT '{}', description TEXT, construction_days INTEGER NOT NULL DEFAULT 1,
  is_active BOOLEAN DEFAULT TRUE, research_project_id TEXT,
  operation_mode TEXT NOT NULL DEFAULT 'SCALABLE' CHECK (operation_mode IN ('SCALABLE', 'BINARY', 'THRESHOLD')),
  minimum_operating_ratio NUMERIC(12,6) NOT NULL DEFAULT 0 CHECK (minimum_operating_ratio BETWEEN 0 AND 1),
  condition_curve_version TEXT NOT NULL DEFAULT 'v1',
  base_condition_decay NUMERIC(12,6) NOT NULL DEFAULT 1,
  maintenance_wear_multiplier NUMERIC(12,6) NOT NULL DEFAULT 2,
  repair_target_condition NUMERIC(10,4) NOT NULL DEFAULT 100,
  repair_materials_per_point NUMERIC(20,8) NOT NULL DEFAULT 1,
  repair_components_per_point NUMERIC(20,8) NOT NULL DEFAULT 1,
  base_condition_decay_ppm BIGINT GENERATED ALWAYS AS (earth_multiplier_to_ppm(base_condition_decay)) STORED,
  maintenance_wear_multiplier_ppm BIGINT GENERATED ALWAYS AS (earth_multiplier_to_ppm(maintenance_wear_multiplier)) STORED,
  repair_materials_per_point_ppm BIGINT GENERATED ALWAYS AS (ROUND(repair_materials_per_point * 1000000)::BIGINT) STORED,
  repair_components_per_point_ppm BIGINT GENERATED ALWAYS AS (ROUND(repair_components_per_point * 1000000)::BIGINT) STORED,
  service_type TEXT,
  base_service_capacity_units BIGINT NOT NULL DEFAULT 0,
  default_price_credit_units BIGINT NOT NULL DEFAULT 0,
  service_mode TEXT NOT NULL DEFAULT 'PRIVATE' CHECK (service_mode IN ('PRIVATE', 'PUBLIC_CONTRACT', 'FREE')),
  operating_service_cost_units BIGINT NOT NULL DEFAULT 0,
  operating_cost_recipient_type TEXT NOT NULL DEFAULT 'NONE',
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (tier BETWEEN 1 AND 5)
);
CREATE UNIQUE INDEX IF NOT EXISTS building_catalog_type_tier_uq ON building_catalog (building_type, tier);

CREATE TABLE IF NOT EXISTS building_economic_rule_versions (
  catalog_id TEXT NOT NULL REFERENCES building_catalog(id) ON DELETE CASCADE,
  rules_version TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  production_recipes JSONB NOT NULL DEFAULT '{}'::JSONB,
  upkeep JSONB NOT NULL DEFAULT '{}'::JSONB,
  condition_curve_version TEXT NOT NULL DEFAULT 'v1',
  condition_decay_ppm BIGINT NOT NULL DEFAULT 1000000 CHECK (condition_decay_ppm >= 0),
  repair_costs JSONB NOT NULL DEFAULT '{}'::JSONB,
  service_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (service_capacity_units >= 0),
  service_price_units BIGINT NOT NULL DEFAULT 0 CHECK (service_price_units >= 0),
  service_matching_rules JSONB NOT NULL DEFAULT '{}'::JSONB,
  operation_mode TEXT NOT NULL DEFAULT 'SCALABLE',
  minimum_operating_ratio_ppm BIGINT NOT NULL DEFAULT 0 CHECK (minimum_operating_ratio_ppm BETWEEN 0 AND 1000000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (catalog_id, rules_version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  UNIQUE (catalog_id, effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS building_economic_rule_versions_effective_idx
  ON building_economic_rule_versions (catalog_id, effective_from_game_day DESC);

CREATE TABLE IF NOT EXISTS corporation_building_unlocks (
  corporation_id TEXT NOT NULL REFERENCES corporations(id), catalog_id TEXT NOT NULL REFERENCES building_catalog(id),
  research_project_id TEXT,
  status TEXT NOT NULL DEFAULT 'unlocked' CHECK (status IN ('unlocked','revoked')),
  unlocked_game_day BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY (corporation_id, catalog_id)
);

CREATE UNLOGGED TABLE IF NOT EXISTS settlement_effects (
  id BIGINT PRIMARY KEY, game_day BIGINT NOT NULL, phase TEXT NOT NULL, shard SMALLINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id), account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id), delta BIGINT NOT NULL, reason_code TEXT NOT NULL, source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNLOGGED TABLE IF NOT EXISTS settlement_effect_nets (
  id BIGINT PRIMARY KEY, game_day BIGINT NOT NULL, phase TEXT NOT NULL, shard SMALLINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id), account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id), delta BIGINT NOT NULL, reason_code TEXT NOT NULL, source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE (game_day, phase, shard, account_id, asset_id)
);

CREATE TABLE IF NOT EXISTS economy_shadow_openings (
  game_day BIGINT NOT NULL, owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id), owner_id TEXT NOT NULL,
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id), legacy_units BIGINT NOT NULL, v2_units BIGINT NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (game_day, owner_economic_id, asset_id)
);
CREATE TABLE IF NOT EXISTS economy_shadow_reconciliations (
  game_day BIGINT NOT NULL, owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id), owner_id TEXT NOT NULL,
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id), legacy_opening_units BIGINT NOT NULL, v2_opening_units BIGINT NOT NULL,
  legacy_closing_units BIGINT NOT NULL, v2_closing_units BIGINT NOT NULL, legacy_delta_units BIGINT NOT NULL, v2_delta_units BIGINT NOT NULL,
  difference_units BIGINT NOT NULL, difference_kind TEXT NOT NULL, details JSONB NOT NULL DEFAULT '{}'::jsonb,
  reconciled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (game_day, owner_economic_id, asset_id)
);
CREATE TABLE IF NOT EXISTS economy_shadow_runs (
  game_day BIGINT PRIMARY KEY, status TEXT NOT NULL, owners_checked BIGINT NOT NULL DEFAULT 0, assets_checked BIGINT NOT NULL DEFAULT 0,
  differences BIGINT NOT NULL DEFAULT 0, absolute_difference_units NUMERIC(30,0) NOT NULL DEFAULT 0,
  unexplained_difference BOOLEAN NOT NULL DEFAULT FALSE, error_message TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, completed_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS economic_entry_partitions (
  from_game_day BIGINT PRIMARY KEY, to_game_day BIGINT NOT NULL UNIQUE, partition_name TEXT NOT NULL UNIQUE,
  provisioned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Columns introduced as forward migrations are declared here as well so a
-- fresh install has the same catalog shape as an installation upgraded in
-- place. IF NOT EXISTS keeps this block safe for schema reconciliation.
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS catalog_id TEXT;
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS effects JSONB NOT NULL DEFAULT '{}';
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS is_original BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE corporation_membership_requests ADD COLUMN IF NOT EXISTS requested_game_day BIGINT NOT NULL DEFAULT 0;
ALTER TABLE governance_rules ADD COLUMN IF NOT EXISTS quorum_threshold NUMERIC(10,4) NOT NULL DEFAULT 0;
ALTER TABLE governance_rules ADD COLUMN IF NOT EXISTS approval_threshold NUMERIC(10,4) NOT NULL DEFAULT 0;
ALTER TABLE governance_rules ADD COLUMN IF NOT EXISTS voting_period_days INTEGER NOT NULL DEFAULT 3;
ALTER TABLE governance_rules ADD COLUMN IF NOT EXISTS implementation_delay_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE governance_rules ADD COLUMN IF NOT EXISTS effective_from_game_day BIGINT NOT NULL DEFAULT 1;
ALTER TABLE governance_rules ADD COLUMN IF NOT EXISTS effective_to_game_day BIGINT;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS governance_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS action_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS proposal_schema_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS action_handler_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS snapshot_hash TEXT;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS eligible_voter_count BIGINT;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS eligibility_cutoff_game_day BIGINT;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS decision_status TEXT NOT NULL DEFAULT 'scheduled';
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS conflict_key TEXT;
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS max_active_proposals_per_creator INTEGER NOT NULL DEFAULT 5;
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS max_active_proposals_per_institution INTEGER NOT NULL DEFAULT 50;
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS proposal_creation_cooldown_minutes INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS memberships_city_joined_human_idx ON memberships(city_id, joined_game_day, human_id);
CREATE INDEX IF NOT EXISTS memberships_corporation_joined_human_idx ON memberships(corporation_id, joined_game_day, human_id);
ALTER TABLE constitutional_rules ADD COLUMN IF NOT EXISTS id TEXT;
ALTER TABLE constitutional_rules ADD COLUMN IF NOT EXISTS part_number INTEGER;
ALTER TABLE constitutional_rules ADD COLUMN IF NOT EXISTS rule_number TEXT;
ALTER TABLE constitutional_rules ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE constitutional_rules ADD COLUMN IF NOT EXISTS default_value TEXT;
ALTER TABLE constitutional_rules ADD COLUMN IF NOT EXISTS authority TEXT;
ALTER TABLE humans ADD COLUMN IF NOT EXISTS account_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE humans ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS charter_rules TEXT;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS food_used NUMERIC(20,6) NOT NULL DEFAULT 0;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS energy_used NUMERIC(20,6) NOT NULL DEFAULT 0;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS compute_used NUMERIC(20,6) NOT NULL DEFAULT 0;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS credits_for_resources NUMERIC(20,2) NOT NULL DEFAULT 0;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS life_condition_after INTEGER NOT NULL DEFAULT 100;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS paid NUMERIC(20,2) NOT NULL DEFAULT 0;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS unpaid NUMERIC(20,2) NOT NULL DEFAULT 0;
ALTER TABLE personal_life_maintenance ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'completed';
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE human_life_conditions ADD COLUMN IF NOT EXISTS score INTEGER NOT NULL DEFAULT 100;
ALTER TABLE human_life_conditions ADD COLUMN IF NOT EXISTS updated_game_day BIGINT NOT NULL DEFAULT 0;
ALTER TABLE human_life_conditions ADD COLUMN IF NOT EXISTS last_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE technologies ADD COLUMN IF NOT EXISTS required_compute NUMERIC(20,6) NOT NULL DEFAULT 0;
ALTER TABLE technologies ADD COLUMN IF NOT EXISTS cost_credits NUMERIC(20,2) NOT NULL DEFAULT 0;
ALTER TABLE technologies ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE world_state ADD COLUMN IF NOT EXISTS last_scheduler_at TIMESTAMPTZ;
ALTER TABLE world_state ADD COLUMN IF NOT EXISTS daily_settlement_mode TEXT NOT NULL DEFAULT 'profile_resources';
ALTER TABLE net_worth_snapshots ADD COLUMN IF NOT EXISTS commodity_valuation NUMERIC(20,2) NOT NULL DEFAULT 0;
ALTER TABLE net_worth_snapshots ADD COLUMN IF NOT EXISTS equity_valuation NUMERIC(20,2) NOT NULL DEFAULT 0;
ALTER TABLE net_worth_snapshots ADD COLUMN IF NOT EXISTS real_estate_valuation NUMERIC(20,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS earth_schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checksum TEXT NOT NULL
);
