-- EARTH PostgreSQL Canonical Schema
--
-- Authoritative, self-contained schema representing the current clean database
-- state from scratch through migration 080.
--
-- This script provisions a fresh, empty database in one step.
-- When introducing new schema changes:
-- 1. Create a forward migration in db/migrations/NNN_description.sql
-- 2. Update this canonical db/schema.sql script to reflect the new state.
--
-- Run with: psql "" -f db/schema.sql
-- Followed by: psql "" -f db/seed.sql (if sample data is needed).

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
  status TEXT NOT NULL CHECK (status IN ('active','distressed','insolvent','bankrupt','dissolved')),
  since_game_day BIGINT NOT NULL,
  recovery_game_day BIGINT,
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS financial_states_status_idx ON financial_states(status, institution_kind);

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
  status TEXT NOT NULL CHECK (status IN ('active','distressed','insolvent','bankrupt')),
  since_game_day BIGINT NOT NULL,
  protected_credits NUMERIC(20,2) NOT NULL DEFAULT 100,
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS personal_financial_status_idx ON personal_financial_states(status, since_game_day);

CREATE TABLE IF NOT EXISTS tax_rules (
  id TEXT PRIMARY KEY,
  scope TEXT NOT NULL,
  category TEXT NOT NULL,
  rate NUMERIC(10,6) NOT NULL CHECK (rate >= 0 AND rate <= 1),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  version INTEGER NOT NULL DEFAULT 1
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
  game_day BIGINT NOT NULL
);

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
  reserved_credits NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (reserved_credits >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS market_orders_book_idx ON market_orders(product, status, limit_price, created_at);
CREATE INDEX IF NOT EXISTS market_orders_matching_idx ON market_orders(product, side, status, limit_price, created_at);
CREATE INDEX IF NOT EXISTS market_orders_reserved_idx ON market_orders(human_id, side, status, reserved_credits);
CREATE UNIQUE INDEX IF NOT EXISTS market_orders_human_correlation_idx ON market_orders(human_id, correlation_id) WHERE correlation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS market_trades (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES market_orders(id),
  product TEXT NOT NULL,
  quantity NUMERIC(20,6) NOT NULL CHECK (quantity > 0),
  clearing_price NUMERIC(20,2) NOT NULL CHECK (clearing_price > 0),
  game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_market_trades_order ON market_trades(order_id);

CREATE TABLE IF NOT EXISTS market_ohlc_snapshots (
  id UUID PRIMARY KEY,
  commodity TEXT NOT NULL CHECK (commodity IN ('material','components','energy','compute','food')),
  game_day BIGINT NOT NULL,
  open_price NUMERIC(20,6) NOT NULL,
  high_price NUMERIC(20,6) NOT NULL,
  low_price NUMERIC(20,6) NOT NULL,
  close_price NUMERIC(20,6) NOT NULL,
  volume NUMERIC(20,6) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (commodity, game_day)
);
CREATE INDEX IF NOT EXISTS idx_market_ohlc_commodity_day ON market_ohlc_snapshots(commodity, game_day DESC);

CREATE TABLE IF NOT EXISTS commodity_futures_contracts (
  id UUID PRIMARY KEY,
  buyer_id TEXT NOT NULL REFERENCES humans(id),
  seller_id TEXT REFERENCES humans(id),
  commodity TEXT NOT NULL CHECK (commodity IN ('material','components','energy','compute','food')),
  contract_size NUMERIC(20,6) NOT NULL CHECK (contract_size > 0),
  strike_price NUMERIC(20,6) NOT NULL CHECK (strike_price > 0),
  expiry_game_day BIGINT NOT NULL,
  premium NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','active','exercised','expired','cancelled')),
  created_game_day BIGINT NOT NULL,
  settled_game_day BIGINT,
  settled_pnl NUMERIC(20,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_futures_participant ON commodity_futures_contracts(buyer_id, seller_id, status);
CREATE INDEX IF NOT EXISTS idx_futures_expiry ON commodity_futures_contracts(status, expiry_game_day);
CREATE INDEX IF NOT EXISTS idx_futures_settlement ON commodity_futures_contracts(commodity, status, expiry_game_day);

CREATE TABLE IF NOT EXISTS daily_settlement_profiles (
  owner_id TEXT PRIMARY KEY,
  owner_kind TEXT NOT NULL CHECK (owner_kind IN ('human', 'city', 'corporation', 'earth')),
  profile_version BIGINT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'dirty' CHECK (status IN ('clean', 'dirty')),
  effective_game_day BIGINT NOT NULL DEFAULT 0,
  last_settled_game_day BIGINT NOT NULL DEFAULT 0,
  credits_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  energy_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  food_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  materials_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  components_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  compute_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  input_fingerprint TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS daily_settlement_profiles_due_idx
  ON daily_settlement_profiles (status, last_settled_game_day, owner_kind);

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

CREATE TABLE IF NOT EXISTS institutions (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('OUC','CORPORATION','CITY')),
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  administrator_human_id TEXT REFERENCES humans(id)
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
  ownership_class TEXT NOT NULL CHECK (ownership_class IN ('private','civic')),
  operating_policy TEXT NOT NULL DEFAULT 'balanced' CHECK (operating_policy IN ('balanced','high_output','eco_reserve','overclock')),
  auto_repair_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  daily_operating_credits NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (daily_operating_credits >= 0),
  resource_output_amount NUMERIC(20,6) NOT NULL DEFAULT 0 CHECK (resource_output_amount >= 0),
  resource_output_type TEXT CHECK (resource_output_type IS NULL OR resource_output_type IN ('material','components','energy','compute','food')),
  construction_started_game_day BIGINT NOT NULL,
  construction_complete_game_day BIGINT,
  construction_progress NUMERIC(5,2) NOT NULL DEFAULT 0.0 CHECK (construction_progress >= 0.0 AND construction_progress <= 100.0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('under_construction','active','damaged','derelict','decommissioned')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_settled_game_day BIGINT
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
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (building_id, day)
);
CREATE INDEX IF NOT EXISTS idx_bldg_journal_city_day ON building_settlement_journals(city_id, day DESC);

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
CREATE INDEX IF NOT EXISTS idx_civic_div_city_day ON civic_dividend_payouts(city_id, day DESC);

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
  opens_at TIMESTAMPTZ NOT NULL,
  closes_at TIMESTAMPTZ NOT NULL,
  rule_version_id TEXT,
  quorum NUMERIC(10,6) NOT NULL DEFAULT 0.25,
  approval_threshold NUMERIC(10,6) NOT NULL DEFAULT 0.5,
  implementation_delay_days INTEGER NOT NULL DEFAULT 1,
  outcome TEXT NOT NULL DEFAULT 'pending' CHECK (outcome IN ('pending','passed','rejected','no_quorum')),
  implementation_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  target_category TEXT,
  target_value_json JSONB,
  executed_at TIMESTAMPTZ,
  execution_status TEXT NOT NULL DEFAULT 'not_ready' CHECK (execution_status IN ('not_ready','ready','queued','executed','skipped','challenged','voided')),
  correlation_id TEXT,
  closes_game_day BIGINT,
  closes_game_minute INTEGER CHECK (closes_game_minute BETWEEN 0 AND 1439),
  implementation_game_day BIGINT,
  implementation_game_minute INTEGER CHECK (implementation_game_minute BETWEEN 0 AND 1439)
);
CREATE UNIQUE INDEX IF NOT EXISTS proposals_institution_correlation_idx ON proposals(institution_id, correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS proposals_game_deadline_idx ON proposals(status, closes_game_day, closes_game_minute);
CREATE INDEX IF NOT EXISTS idx_proposals_institution_status ON proposals(institution_id, status);

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
  version INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','superseded','repealed')),
  created_by TEXT NOT NULL REFERENCES humans(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (institution_id, category, version)
);
CREATE INDEX IF NOT EXISTS idx_gov_rules_inst_cat ON governance_rules(institution_id, category, status);

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

CREATE TABLE IF NOT EXISTS technologies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  owner_id TEXT,
  progress NUMERIC(5,2) NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  metadata JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS research_projects (
  id TEXT PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technologies(id),
  owner_id TEXT NOT NULL REFERENCES humans(id),
  budget NUMERIC(20,2) NOT NULL DEFAULT 0,
  progress NUMERIC(10,4) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  started_game_day BIGINT NOT NULL,
  focus TEXT NOT NULL DEFAULT 'efficiency' CHECK (focus IN ('efficiency','durability','safety','cost'))
);

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

CREATE TABLE IF NOT EXISTS human_technology_adoptions (
  human_id TEXT NOT NULL REFERENCES humans(id),
  technology_id TEXT NOT NULL REFERENCES technologies(id),
  adopted_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','superseded','revoked')),
  PRIMARY KEY (human_id, technology_id)
);
CREATE INDEX IF NOT EXISTS human_technology_adoptions_human_idx ON human_technology_adoptions(human_id);
CREATE INDEX IF NOT EXISTS human_technology_adoptions_technology_idx ON human_technology_adoptions(technology_id);

CREATE TABLE IF NOT EXISTS human_technology_subscriptions (
  human_id TEXT NOT NULL REFERENCES humans(id),
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  technology_key TEXT NOT NULL,
  subscription_cost_credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  subscribed_game_day BIGINT,
  unsubscribed_game_day BIGINT,
  last_billed_game_day BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (human_id, technology_key)
);
CREATE INDEX IF NOT EXISTS human_technology_subscriptions_human_idx
  ON human_technology_subscriptions(human_id, status);

-- -----------------------------------------------------------------------------
-- 10. Contracts, Supply & Arbitration
-- -----------------------------------------------------------------------------

/* RETIRED: negotiated_contracts, contract_disputes, supply_contracts,
   contract_escrow_vaults, and contract_delivery_ticks are removed by
   migration 121. Market futures remain in commodity_futures_contracts. */
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

CREATE TABLE IF NOT EXISTS earth_schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checksum TEXT NOT NULL
);
