-- EARTH ACTIVE MIGRATION: clean baseline
-- GENERATED FILE: run npm run db:baseline:build; do not edit directly

-- =====================================================
-- SECTION 1: SCHEMA
-- =====================================================

-- EARTH clean baseline schema. No historical compatibility objects belong here.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE auth_accounts (
  id TEXT PRIMARY KEY,
  house_id TEXT,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL CHECK (password_iterations > 0),
  email_verified_at TIMESTAMPTZ,
  mfa_secret TEXT,
  mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE auth_email_deliveries (
  id BIGSERIAL PRIMARY KEY,
  correlation_id TEXT NOT NULL UNIQUE,
  account_id TEXT REFERENCES auth_accounts(id),
  recipient_masked TEXT NOT NULL,
  action TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_message_id TEXT,
  status TEXT NOT NULL,
  error_code TEXT,
  error_message TEXT,
  accepted_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE houses (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL UNIQUE REFERENCES auth_accounts(id),
  current_human_id TEXT,
  house_name TEXT NOT NULL,
  motto TEXT,
  dynasty_legacy BIGINT NOT NULL DEFAULT 0 CHECK (dynasty_legacy >= 0),
  generation INTEGER NOT NULL DEFAULT 1 CHECK (generation > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE humans (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES auth_accounts(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  display_name TEXT NOT NULL,
  birth_game_day BIGINT NOT NULL DEFAULT 1,
  death_game_day BIGINT,
  age_years INTEGER NOT NULL DEFAULT 18 CHECK (age_years >= 0),
  standing BIGINT NOT NULL DEFAULT 0 CHECK (standing >= 0),
  final_legacy BIGINT NOT NULL DEFAULT 0 CHECK (final_legacy >= 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DECEASED')),
  UNIQUE (id, house_id)
);
ALTER TABLE auth_accounts ADD CONSTRAINT auth_accounts_house_fk FOREIGN KEY (house_id) REFERENCES houses(id);
ALTER TABLE houses ADD CONSTRAINT houses_current_human_fk FOREIGN KEY (current_human_id) REFERENCES humans(id);
CREATE TABLE auth_sessions (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES auth_accounts(id), human_id TEXT REFERENCES humans(id), token_hash TEXT NOT NULL UNIQUE, expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE auth_login_attempts (email TEXT PRIMARY KEY, window_started_at TIMESTAMPTZ NOT NULL, attempt_count INTEGER NOT NULL CHECK (attempt_count >= 0), blocked_until TIMESTAMPTZ);
CREATE TABLE auth_action_tokens (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES auth_accounts(id), human_id TEXT REFERENCES humans(id), token_hash TEXT NOT NULL UNIQUE, action TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL, consumed_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE house_succession_plans (house_id TEXT PRIMARY KEY REFERENCES houses(id), successor_name TEXT NOT NULL, registered_game_day BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE succession_events (id BIGSERIAL PRIMARY KEY, house_id TEXT NOT NULL REFERENCES houses(id), predecessor_human_id TEXT NOT NULL REFERENCES humans(id), successor_human_id TEXT REFERENCES humans(id), death_game_day BIGINT NOT NULL, effective_game_day BIGINT NOT NULL, generation INTEGER NOT NULL, status TEXT NOT NULL, correlation_id TEXT NOT NULL UNIQUE);

CREATE TABLE world_state (id TEXT PRIMARY KEY, game_day BIGINT NOT NULL CHECK (game_day >= 0), game_minute INTEGER NOT NULL CHECK (game_minute BETWEEN 0 AND 1439), world_seed TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE institutions (id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('EARTH','CORPORATION','BANK')), name TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE corporations (
  id TEXT PRIMARY KEY REFERENCES institutions(id),
  charter_version TEXT NOT NULL DEFAULT 'corporation-charter-v1',
  admission_policy TEXT NOT NULL DEFAULT 'OPEN',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','DISSOLVING','DISSOLVED')),
  created_game_day BIGINT NOT NULL DEFAULT 1
);
CREATE TABLE territories (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  name TEXT NOT NULL,
  territory_type TEXT NOT NULL DEFAULT 'PRIMARY',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','UNGOVERNED')),
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  created_game_day BIGINT NOT NULL DEFAULT 1,
  UNIQUE (id, corporation_id)
);
CREATE UNIQUE INDEX territories_one_active_primary_idx
  ON territories (corporation_id)
  WHERE is_primary = TRUE AND status = 'ACTIVE';
CREATE TABLE house_affiliations (
  id BIGSERIAL PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  primary_territory_id TEXT,
  joined_game_day BIGINT NOT NULL,
  left_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','LEFT','REMOVED')),
  FOREIGN KEY (primary_territory_id, corporation_id) REFERENCES territories(id, corporation_id),
  CHECK (left_game_day IS NULL OR left_game_day >= joined_game_day)
);
CREATE UNIQUE INDEX house_affiliations_one_active_idx
  ON house_affiliations (house_id)
  WHERE status = 'ACTIVE';
CREATE TABLE territory_capacity_state (
  territory_id TEXT PRIMARY KEY REFERENCES territories(id),
  game_day BIGINT NOT NULL,
  active_house_count INTEGER NOT NULL DEFAULT 0 CHECK (active_house_count >= 0),
  house_capacity BIGINT NOT NULL DEFAULT 0 CHECK (house_capacity >= 0),
  population_capacity BIGINT NOT NULL DEFAULT 0 CHECK (population_capacity >= 0),
  private_slot_capacity BIGINT NOT NULL DEFAULT 0 CHECK (private_slot_capacity >= 0),
  public_slot_capacity BIGINT NOT NULL DEFAULT 0 CHECK (public_slot_capacity >= 0),
  private_slots_used BIGINT NOT NULL DEFAULT 0 CHECK (private_slots_used >= 0),
  public_slots_used BIGINT NOT NULL DEFAULT 0 CHECK (public_slots_used >= 0),
  housing_capacity BIGINT NOT NULL DEFAULT 0 CHECK (housing_capacity >= 0),
  health_capacity BIGINT NOT NULL DEFAULT 0 CHECK (health_capacity >= 0),
  energy_capacity BIGINT NOT NULL DEFAULT 0 CHECK (energy_capacity >= 0),
  connectivity_capacity BIGINT NOT NULL DEFAULT 0 CHECK (connectivity_capacity >= 0),
  service_capacity JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(service_capacity) = 'object'),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX territory_capacity_state_game_day_idx ON territory_capacity_state (game_day, territory_id);
CREATE TABLE institution_governance_roles (id BIGSERIAL PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), human_id TEXT NOT NULL REFERENCES humans(id), role_code TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE constitutional_rules (id TEXT PRIMARY KEY, part_number INTEGER NOT NULL, article_number INTEGER NOT NULL DEFAULT 1, rule_number TEXT NOT NULL UNIQUE, title TEXT NOT NULL, description TEXT NOT NULL, default_value TEXT NOT NULL, permitted_values TEXT, authority TEXT NOT NULL DEFAULT 'EARTH', active BOOLEAN NOT NULL DEFAULT TRUE, updated_game_day BIGINT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE governance_rules (id TEXT PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), name TEXT NOT NULL, category TEXT NOT NULL, value_json JSONB NOT NULL DEFAULT '{}'::jsonb, quorum_threshold NUMERIC NOT NULL CHECK (quorum_threshold >= 0 AND quorum_threshold <= 1), approval_threshold NUMERIC NOT NULL CHECK (approval_threshold >= 0 AND approval_threshold <= 1), voting_period_days INTEGER NOT NULL CHECK (voting_period_days > 0), implementation_delay_days INTEGER NOT NULL DEFAULT 0 CHECK (implementation_delay_days >= 0), version INTEGER NOT NULL CHECK (version > 0), status TEXT NOT NULL, created_by TEXT, effective_from_game_day BIGINT NOT NULL DEFAULT 1, effective_to_game_day BIGINT, UNIQUE (institution_id, category, version));
CREATE TABLE economic_policy_rules (code TEXT PRIMARY KEY, output_multiplier NUMERIC(8,4) NOT NULL CHECK (output_multiplier >= 0), cost_multiplier NUMERIC(8,4) NOT NULL CHECK (cost_multiplier >= 0), decay_multiplier NUMERIC(8,4) NOT NULL CHECK (decay_multiplier >= 0), is_selectable BOOLEAN NOT NULL DEFAULT TRUE, description TEXT NOT NULL);

CREATE TABLE economic_assets (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, asset_kind TEXT NOT NULL CHECK (asset_kind IN ('CREDIT','RESOURCE')));
CREATE TABLE owner_registry (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL CHECK (owner_type IN ('EARTH','CORPORATION','HOUSE','BANK','SYSTEM','ORGANIZATION')), economic_id TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE economic_account_types (code TEXT PRIMARY KEY);
CREATE TABLE economic_account_policies (
  owner_type TEXT NOT NULL CHECK (owner_type IN ('EARTH','CORPORATION','HOUSE','BANK','SYSTEM','ORGANIZATION')),
  account_type TEXT NOT NULL REFERENCES economic_account_types(code),
  allowed_asset_kind TEXT NOT NULL CHECK (allowed_asset_kind IN ('CREDIT','RESOURCE','ANY')),
  player_visible BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (owner_type, account_type, allowed_asset_kind)
);
CREATE TABLE economic_accounts (id BIGSERIAL PRIMARY KEY, owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), asset_id INTEGER NOT NULL REFERENCES economic_assets(id), account_type TEXT NOT NULL REFERENCES economic_account_types(code), balance_units BIGINT NOT NULL DEFAULT 0 CHECK (balance_units >= 0), status TEXT NOT NULL DEFAULT 'ACTIVE', UNIQUE (owner_economic_id, asset_id, account_type));
CREATE TABLE economic_transaction_kinds (code TEXT PRIMARY KEY, semantic_class TEXT NOT NULL CHECK (semantic_class IN ('ASSET_TRANSFER','CREDIT_ISSUANCE','CREDIT_RETIREMENT','RESOURCE_PRODUCTION','RESOURCE_CONSUMPTION')), asset_kind TEXT NOT NULL CHECK (asset_kind IN ('CREDIT','RESOURCE','ANY')), description TEXT NOT NULL);
CREATE TABLE economic_source_types (code TEXT PRIMARY KEY, source_class TEXT NOT NULL CHECK (source_class IN ('ACTOR','SYSTEM','MARKET','GOVERNANCE','SETTLEMENT','INTERACTIVE')), description TEXT NOT NULL);
CREATE TABLE economic_transactions (id BIGSERIAL PRIMARY KEY, correlation_id TEXT NOT NULL UNIQUE, game_day BIGINT NOT NULL, game_minute INTEGER NOT NULL, transaction_kind TEXT NOT NULL, source_type TEXT NOT NULL, source_id TEXT, rules_version TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE economic_entries (id BIGSERIAL PRIMARY KEY, transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id), account_id BIGINT NOT NULL REFERENCES economic_accounts(id), delta_units BIGINT NOT NULL CHECK (delta_units <> 0), asset_id INTEGER NOT NULL REFERENCES economic_assets(id), UNIQUE (transaction_id, account_id));
CREATE TABLE monetary_supply_snapshots (game_day BIGINT PRIMARY KEY, issued_total_units BIGINT NOT NULL, retired_total_units BIGINT NOT NULL, circulating_units BIGINT NOT NULL, escrow_units BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());

CREATE TABLE building_catalog (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 5), ownership_scope TEXT NOT NULL DEFAULT 'PRIVATE' CHECK (ownership_scope IN ('PRIVATE','PUBLIC')), construction_credit_units BIGINT NOT NULL CHECK (construction_credit_units >= 0), construction_minutes INTEGER NOT NULL CHECK (construction_minutes > 0), operating_credit_units BIGINT NOT NULL CHECK (operating_credit_units >= 0), resource_input_units JSONB NOT NULL DEFAULT '{}'::jsonb, resource_output_units JSONB NOT NULL DEFAULT '{}'::jsonb, service_type TEXT, service_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (service_capacity_units >= 0), slot_footprint INTEGER NOT NULL DEFAULT 1 CHECK (slot_footprint > 0), definition_version TEXT NOT NULL);
CREATE TABLE buildings (id TEXT PRIMARY KEY, owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), territory_id TEXT NOT NULL REFERENCES territories(id), catalog_id TEXT NOT NULL REFERENCES building_catalog(id), status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','DESTROYED')), started_game_day BIGINT NOT NULL, UNIQUE (id, owner_economic_id));
CREATE TABLE building_catalog_effects (catalog_id TEXT NOT NULL REFERENCES building_catalog(id), effect_code TEXT NOT NULL, effect_value BIGINT NOT NULL CHECK (effect_value >= 0), rules_version TEXT NOT NULL DEFAULT 'building-effects-v1', PRIMARY KEY (catalog_id, effect_code, rules_version));

CREATE TABLE market_instruments (id TEXT PRIMARY KEY, symbol TEXT NOT NULL UNIQUE, instrument_type TEXT NOT NULL DEFAULT 'SPOT' CHECK (instrument_type = 'SPOT'), asset_id INTEGER NOT NULL REFERENCES economic_assets(id), quote_asset_id INTEGER NOT NULL REFERENCES economic_assets(id), lot_size_units BIGINT NOT NULL DEFAULT 1 CHECK (lot_size_units > 0), price_tick_units BIGINT NOT NULL DEFAULT 1 CHECK (price_tick_units > 0), rules_version TEXT NOT NULL DEFAULT 'spot-market-v1', status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE market_batches (id BIGSERIAL PRIMARY KEY, game_day BIGINT NOT NULL, game_minute INTEGER NOT NULL, status TEXT NOT NULL CHECK (status IN ('OPEN','CLEARING','COMPLETED','FAILED')), correlation_id TEXT NOT NULL UNIQUE, completed_transaction_id BIGINT REFERENCES economic_transactions(id));
CREATE TABLE market_orders (id TEXT PRIMARY KEY, batch_id BIGINT NOT NULL REFERENCES market_batches(id), instrument_id TEXT NOT NULL REFERENCES market_instruments(id), owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), side TEXT NOT NULL CHECK (side IN ('BUY','SELL')), quantity_units BIGINT NOT NULL CHECK (quantity_units > 0), remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0), limit_price_units BIGINT NOT NULL CHECK (limit_price_units > 0), buyer_fee_bps INTEGER NOT NULL DEFAULT 0 CHECK (buyer_fee_bps >= 0), seller_fee_bps INTEGER NOT NULL DEFAULT 0 CHECK (seller_fee_bps >= 0), status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','PARTIAL','FILLED','CANCELLED')), rules_version TEXT NOT NULL, correlation_id TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK (remaining_units <= quantity_units));
CREATE TABLE market_order_reservations (id BIGSERIAL PRIMARY KEY, order_id TEXT NOT NULL REFERENCES market_orders(id), escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id), asset_id INTEGER NOT NULL REFERENCES economic_assets(id), reserved_units BIGINT NOT NULL CHECK (reserved_units > 0), remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0 AND remaining_units <= reserved_units), status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CONSUMED','RELEASED')), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (order_id, asset_id));
CREATE TABLE market_fills (id BIGSERIAL PRIMARY KEY, batch_id BIGINT NOT NULL REFERENCES market_batches(id), instrument_id TEXT NOT NULL REFERENCES market_instruments(id), buy_order_id TEXT NOT NULL REFERENCES market_orders(id), sell_order_id TEXT NOT NULL REFERENCES market_orders(id), buyer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), seller_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), quantity_units BIGINT NOT NULL CHECK (quantity_units > 0), price_units BIGINT NOT NULL CHECK (price_units > 0), gross_quote_units BIGINT NOT NULL CHECK (gross_quote_units > 0), buyer_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (buyer_fee_units >= 0), seller_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (seller_fee_units >= 0), economic_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id), sequence_no INTEGER NOT NULL, UNIQUE (batch_id, sequence_no));
CREATE TABLE market_instrument_state (instrument_id TEXT PRIMARY KEY REFERENCES market_instruments(id), last_completed_batch_id BIGINT, last_clearing_price_units BIGINT, best_bid_units BIGINT, best_ask_units BIGINT, open_buy_units BIGINT NOT NULL DEFAULT 0, open_sell_units BIGINT NOT NULL DEFAULT 0, rolling_volume_units BIGINT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE market_candles (instrument_id TEXT NOT NULL REFERENCES market_instruments(id), interval_kind TEXT NOT NULL, period_id BIGINT NOT NULL, open_price_units BIGINT NOT NULL, high_price_units BIGINT NOT NULL, low_price_units BIGINT NOT NULL, close_price_units BIGINT NOT NULL, volume_units BIGINT NOT NULL DEFAULT 0, fill_count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (instrument_id, interval_kind, period_id));

-- Notifications V2: House-owned history with optional Human attribution.
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  human_id TEXT NULL REFERENCES humans(id),
  notification_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  entity_type TEXT NULL,
  entity_id TEXT NULL,
  game_day INTEGER NULL,
  game_minute INTEGER NULL,
  correlation_id TEXT NULL UNIQUE,
  read_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX notifications_house_created_idx ON notifications (house_id, created_at DESC);
CREATE INDEX notifications_house_unread_idx ON notifications (house_id, read_at) WHERE read_at IS NULL;

-- Durable game event journal; not an accounting authority.
CREATE TABLE game_events (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL DEFAULT 'SYSTEM',
  event_type TEXT NOT NULL,
  game_day INTEGER NOT NULL,
  game_minute INTEGER NULL,
  actor_house_id TEXT NULL REFERENCES houses(id),
  actor_human_id TEXT NULL REFERENCES humans(id),
  institution_id TEXT NULL,
  subject_type TEXT NULL,
  subject_id TEXT NULL,
  title TEXT NOT NULL,
  details TEXT NOT NULL,
  correlation_id TEXT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX game_events_category_day_idx ON game_events (category, game_day DESC, created_at DESC);
CREATE INDEX game_events_subject_idx ON game_events (subject_type, subject_id, created_at DESC);
CREATE INDEX game_events_actor_house_idx ON game_events (actor_house_id, created_at DESC);

-- Communications V2: conversations persist by House; messages retain the speaking Human.
CREATE TABLE comm_channels (
  id TEXT PRIMARY KEY,
  scope TEXT NOT NULL CHECK (scope IN ('global', 'corporation', 'community', 'direct')),
  scope_id TEXT NULL,
  name TEXT NOT NULL,
  description TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE comm_direct_conversations (
  channel_id TEXT PRIMARY KEY REFERENCES comm_channels(id) ON DELETE CASCADE,
  participant_low_house_id TEXT NOT NULL REFERENCES houses(id),
  participant_high_house_id TEXT NOT NULL REFERENCES houses(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (participant_low_house_id < participant_high_house_id),
  UNIQUE (participant_low_house_id, participant_high_house_id)
);
CREATE TABLE comm_messages (
  id TEXT PRIMARY KEY,
  channel_id TEXT NOT NULL REFERENCES comm_channels(id) ON DELETE CASCADE,
  sender_house_id TEXT NOT NULL REFERENCES houses(id),
  sender_human_id TEXT NOT NULL REFERENCES humans(id),
  sender_display_name TEXT NOT NULL,
  sender_dynasty_name TEXT NULL,
  body TEXT NOT NULL,
  game_day INTEGER NOT NULL,
  game_minute INTEGER NOT NULL,
  attachments TEXT NOT NULL DEFAULT 'null',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX comm_channels_scope_idx ON comm_channels (scope, scope_id);
CREATE INDEX comm_direct_house_idx ON comm_direct_conversations (participant_low_house_id, participant_high_house_id);
CREATE INDEX comm_messages_channel_created_idx ON comm_messages (channel_id, game_day, created_at);
CREATE INDEX comm_messages_sender_house_idx ON comm_messages (sender_house_id, created_at);

CREATE TABLE bank_deposits (id TEXT PRIMARY KEY, depositor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), principal_units BIGINT NOT NULL CHECK (principal_units > 0), accrued_interest_units BIGINT NOT NULL DEFAULT 0 CHECK (accrued_interest_units >= 0), rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0), maturity_total_game_minute BIGINT NOT NULL, status TEXT NOT NULL, created_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id), payout_transaction_id BIGINT REFERENCES economic_transactions(id), correlation_id TEXT NOT NULL UNIQUE);
CREATE TABLE bank_loans (id TEXT PRIMARY KEY, borrower_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), original_principal_units BIGINT NOT NULL CHECK (original_principal_units > 0), outstanding_principal_units BIGINT NOT NULL CHECK (outstanding_principal_units >= 0), accrued_interest_units BIGINT NOT NULL DEFAULT 0 CHECK (accrued_interest_units >= 0), rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0), status TEXT NOT NULL, origination_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id), correlation_id TEXT NOT NULL UNIQUE);
CREATE TABLE global_bank_balance_sheet (game_day BIGINT PRIMARY KEY, reserve_units BIGINT NOT NULL, performing_loans_units BIGINT NOT NULL, deposit_principal_units BIGINT NOT NULL, liabilities_units BIGINT NOT NULL, assets_units BIGINT NOT NULL, equity_units BIGINT NOT NULL, liquidity_ratio NUMERIC NOT NULL, capital_ratio NUMERIC NOT NULL, status TEXT NOT NULL);

CREATE TABLE tax_governance_rules (scope TEXT NOT NULL CHECK (scope IN ('EARTH','CORPORATION')), category TEXT NOT NULL, minimum_rate_bps INTEGER NOT NULL DEFAULT 0 CHECK (minimum_rate_bps >= 0), maximum_rate_bps INTEGER NOT NULL CHECK (maximum_rate_bps >= minimum_rate_bps AND maximum_rate_bps <= 10000), allowed_tax_base_definitions JSONB NOT NULL CHECK (jsonb_typeof(allowed_tax_base_definitions) = 'array'), beneficiary_scope TEXT NOT NULL CHECK (beneficiary_scope IN ('EARTH','CORPORATION')), rules_version TEXT NOT NULL, PRIMARY KEY (scope, category));
CREATE TABLE tax_rule_versions (id TEXT PRIMARY KEY, tax_rule_id TEXT NOT NULL, scope TEXT NOT NULL CHECK (scope IN ('EARTH','CORPORATION')), category TEXT NOT NULL, version INTEGER NOT NULL, effective_from_game_day BIGINT NOT NULL, effective_to_game_day BIGINT, rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0), tax_base_definition TEXT NOT NULL, beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), authorization_proposal_id TEXT, UNIQUE (tax_rule_id, version), CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day));
CREATE TABLE tax_obligations (id TEXT PRIMARY KEY, taxpayer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), tax_type TEXT NOT NULL, tax_base_units BIGINT NOT NULL CHECK (tax_base_units >= 0), amount_units BIGINT NOT NULL CHECK (amount_units >= 0), rule_version TEXT NOT NULL, game_day BIGINT NOT NULL, status TEXT NOT NULL, payment_transaction_id BIGINT REFERENCES economic_transactions(id));
CREATE TABLE financial_obligations (id TEXT PRIMARY KEY, debtor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), creditor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), obligation_type TEXT NOT NULL CHECK (obligation_type IN ('TAX','ROYALTY','LICENSE_PAYMENT','LOAN_PAYMENT','SERVICE_INVOICE','FINE_FEE')), source_id TEXT, principal_due_units BIGINT NOT NULL CHECK (principal_due_units >= 0), interest_due_units BIGINT NOT NULL DEFAULT 0 CHECK (interest_due_units >= 0), paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0), debtor_account_purpose TEXT NOT NULL DEFAULT 'WALLET', creditor_account_purpose TEXT NOT NULL DEFAULT 'TREASURY', due_game_day BIGINT NOT NULL, priority_class INTEGER NOT NULL DEFAULT 100, rule_version TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PARTIAL','PAID','ARREARS','CANCELLED')), created_game_day BIGINT NOT NULL, payment_transaction_id BIGINT REFERENCES economic_transactions(id), correlation_id TEXT NOT NULL UNIQUE, cancelled_game_day BIGINT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK (paid_units <= principal_due_units + interest_due_units), CHECK ((status = 'PAID' AND paid_units = principal_due_units + interest_due_units) OR status <> 'PAID'));

CREATE TABLE fiscal_periods (id TEXT PRIMARY KEY, period_type TEXT NOT NULL, start_game_day BIGINT NOT NULL, end_game_day BIGINT NOT NULL CHECK (end_game_day >= start_game_day), status TEXT NOT NULL);
CREATE TABLE budget_categories (id TEXT PRIMARY KEY, institution_kind TEXT NOT NULL CHECK (institution_kind = 'CORPORATION'), category_code TEXT NOT NULL, spending_class TEXT NOT NULL CHECK (spending_class IN ('MANDATORY','DISCRETIONARY')), priority INTEGER NOT NULL, UNIQUE (institution_kind, category_code));
CREATE TABLE institution_budget_lines (id TEXT PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), fiscal_period_id TEXT NOT NULL REFERENCES fiscal_periods(id), category_id TEXT NOT NULL REFERENCES budget_categories(id), authorized_units BIGINT NOT NULL CHECK (authorized_units >= 0), committed_units BIGINT NOT NULL DEFAULT 0 CHECK (committed_units >= 0), spent_units BIGINT NOT NULL DEFAULT 0 CHECK (spent_units >= 0), status TEXT NOT NULL, rule_version TEXT NOT NULL, CHECK (authorized_units >= committed_units + spent_units));
CREATE TABLE institution_budget_commitments (id TEXT PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), budget_line_id TEXT NOT NULL REFERENCES institution_budget_lines(id), source_type TEXT NOT NULL, source_id TEXT NOT NULL, original_units BIGINT NOT NULL CHECK (original_units > 0), remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0), status TEXT NOT NULL, due_game_day BIGINT);
CREATE TABLE institution_financial_events (id BIGSERIAL PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), game_day BIGINT NOT NULL, event_type TEXT NOT NULL, amount_units BIGINT NOT NULL CHECK (amount_units >= 0), budget_line_id TEXT REFERENCES institution_budget_lines(id), economic_transaction_id BIGINT REFERENCES economic_transactions(id), correlation_id TEXT NOT NULL UNIQUE);

CREATE TABLE technology_catalog (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'RESEARCH', description TEXT NOT NULL DEFAULT '', patentable BOOLEAN NOT NULL DEFAULT FALSE, patent_exclusivity_days INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'ACTIVE', definition_version TEXT NOT NULL, research_points_required BIGINT NOT NULL CHECK (research_points_required > 0), credit_cost_units BIGINT NOT NULL CHECK (credit_cost_units >= 0), effective_from_game_day BIGINT NOT NULL DEFAULT 0, effective_to_game_day BIGINT);
CREATE TABLE technology_effects (technology_id TEXT NOT NULL REFERENCES technology_catalog(id), effect_type TEXT NOT NULL, target_key TEXT NOT NULL, modifier_bps INTEGER NOT NULL, id BIGINT GENERATED BY DEFAULT AS IDENTITY, modifier_family TEXT NOT NULL DEFAULT 'GENERIC', target_type TEXT NOT NULL DEFAULT 'ASSET', PRIMARY KEY (technology_id, effect_type, target_key));
CREATE TABLE corporation_research_projects (id TEXT PRIMARY KEY, corporation_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), target_type TEXT NOT NULL, target_id TEXT NOT NULL, definition_version TEXT NOT NULL, required_research_points BIGINT NOT NULL, progress_research_points BIGINT NOT NULL DEFAULT 0 CHECK (progress_research_points >= 0), credit_cost_units BIGINT NOT NULL, priority INTEGER NOT NULL DEFAULT 100, started_game_day BIGINT, completed_game_day BIGINT, correlation_id TEXT NOT NULL, definition_snapshot TEXT NOT NULL DEFAULT 'null', created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, status TEXT NOT NULL, funding_transaction_id BIGINT REFERENCES economic_transactions(id));
CREATE TABLE corporation_technology_access (corporation_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), technology_id TEXT NOT NULL REFERENCES technology_catalog(id), access_source TEXT NOT NULL, effective_from_game_day BIGINT NOT NULL, effective_to_game_day BIGINT, source_id TEXT NOT NULL DEFAULT 'BASELINE', created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, status TEXT NOT NULL, PRIMARY KEY (corporation_economic_id, technology_id));
CREATE UNIQUE INDEX corporation_research_projects_correlation_uq ON corporation_research_projects (correlation_id);
CREATE UNIQUE INDEX corporation_research_projects_active_target_idx ON corporation_research_projects (corporation_economic_id, target_type, target_id) WHERE status IN ('QUEUED', 'ACTIVE', 'COMPLETED');
CREATE TABLE technology_patents (
  id TEXT PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id),
  owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  granted_game_day BIGINT NOT NULL CHECK (granted_game_day >= 0),
  exclusive_through_game_day BIGINT NOT NULL CHECK (exclusive_through_game_day >= granted_game_day),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','EXPIRED','REVOKED')),
  granting_project_id TEXT NOT NULL REFERENCES corporation_research_projects(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX technology_patents_one_active_idx ON technology_patents (technology_id) WHERE status = 'ACTIVE';
CREATE INDEX technology_patents_owner_idx ON technology_patents (owner_economic_id, status);
CREATE TABLE technology_public_domain (
  technology_id TEXT PRIMARY KEY REFERENCES technology_catalog(id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  source_patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE technology_license_contracts (
  id TEXT PRIMARY KEY,
  patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  licensor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  licensee_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  upfront_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (upfront_fee_units >= 0),
  daily_fee_units BIGINT NOT NULL DEFAULT 0 CHECK (daily_fee_units >= 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','EXPIRED','TERMINATED')),
  paid_through_game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (licensee_economic_id <> licensor_economic_id),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE INDEX technology_license_contracts_licensee_idx ON technology_license_contracts (licensee_economic_id, status, effective_from_game_day);
CREATE INDEX technology_license_contracts_patent_idx ON technology_license_contracts (patent_id, status);
CREATE TABLE technology_license_payments (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES technology_license_contracts(id),
  payer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  recipient_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL,
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  economic_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE proposals (id TEXT PRIMARY KEY, institution_id TEXT REFERENCES institutions(id), created_by_human_id TEXT NOT NULL REFERENCES humans(id), action_type TEXT NOT NULL, target_type TEXT NOT NULL DEFAULT 'INSTITUTION' CHECK (target_type IN ('INSTITUTION','TERRITORY')), target_id TEXT, target_value JSONB NOT NULL DEFAULT '{}'::jsonb, status TEXT NOT NULL, created_game_day BIGINT NOT NULL, CHECK ((target_type = 'INSTITUTION' AND target_id IS NULL) OR (target_type = 'TERRITORY' AND target_id IS NOT NULL)));
ALTER TABLE tax_rule_versions ADD CONSTRAINT tax_rule_versions_proposal_fk FOREIGN KEY (authorization_proposal_id) REFERENCES proposals(id);
CREATE TABLE ballots (proposal_id TEXT NOT NULL REFERENCES proposals(id), house_id TEXT NOT NULL REFERENCES houses(id), cast_by_human_id TEXT NOT NULL REFERENCES humans(id), choice TEXT NOT NULL, PRIMARY KEY (proposal_id, house_id));
CREATE TABLE event_outbox (id TEXT PRIMARY KEY, event_key TEXT NOT NULL UNIQUE, topic TEXT NOT NULL, aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0), available_at TIMESTAMPTZ NOT NULL DEFAULT now(), locked_at TIMESTAMPTZ, processed_at TIMESTAMPTZ, last_error TEXT, status TEXT NOT NULL DEFAULT 'PENDING', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE scheduler_runs (id BIGSERIAL PRIMARY KEY, game_day BIGINT NOT NULL, phase TEXT NOT NULL, status TEXT NOT NULL, correlation_id TEXT NOT NULL UNIQUE, started_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ);
CREATE TABLE daily_settlement_control (id TEXT PRIMARY KEY CHECK (id = 'WORLD'), status TEXT NOT NULL CHECK (status IN ('awaiting_baseline','active','paused')) DEFAULT 'awaiting_baseline', activated_at TIMESTAMPTZ, activated_by TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE daily_settlement_runs (game_day BIGINT PRIMARY KEY CHECK (game_day >= 1), status TEXT NOT NULL CHECK (status IN ('pending','running','completed','failed','baseline','paused')), current_phase TEXT, attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0), lease_owner TEXT, lease_heartbeat_at TIMESTAMPTZ, rules_version TEXT NOT NULL DEFAULT 'daily-settlement-v1', started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, error_message TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE daily_settlement_phase_runs (id BIGSERIAL PRIMARY KEY, game_day BIGINT NOT NULL REFERENCES daily_settlement_runs(game_day), phase_id TEXT NOT NULL, phase_order INTEGER NOT NULL CHECK (phase_order >= 0), shard INTEGER NOT NULL CHECK (shard >= 0), status TEXT NOT NULL CHECK (status IN ('pending','running','completed','failed')), correlation_id TEXT NOT NULL UNIQUE, attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0), lease_owner TEXT, lease_expires_at TIMESTAMPTZ, started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, error_message TEXT, result JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (game_day, phase_id, shard));
CREATE INDEX daily_settlement_phase_runs_claim_idx ON daily_settlement_phase_runs (game_day, status, lease_expires_at, phase_order, shard);
CREATE INDEX daily_settlement_phase_runs_failures_idx ON daily_settlement_phase_runs (game_day, status) WHERE status = 'failed';
CREATE TABLE house_daily_statements (
  house_id TEXT NOT NULL REFERENCES houses(id),
  game_day BIGINT NOT NULL,
  opening_assets JSONB NOT NULL DEFAULT '{}'::jsonb,
  closing_assets JSONB NOT NULL DEFAULT '{}'::jsonb,
  production JSONB NOT NULL DEFAULT '{}'::jsonb,
  consumption JSONB NOT NULL DEFAULT '{}'::jsonb,
  market_activity JSONB NOT NULL DEFAULT '{}'::jsonb,
  obligations JSONB NOT NULL DEFAULT '{}'::jsonb,
  exceptions JSONB NOT NULL DEFAULT '{}'::jsonb,
  net_credit_units BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (house_id, game_day)
);
CREATE INDEX house_daily_statements_day_idx ON house_daily_statements (game_day, house_id);
CREATE TABLE need_rules (need_code TEXT PRIMARY KEY, service_type_code TEXT NOT NULL, demand_units_per_human BIGINT NOT NULL CHECK (demand_units_per_human > 0), critical_threshold_bps INTEGER NOT NULL CHECK (critical_threshold_bps BETWEEN 0 AND 10000), rules_version TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED')));
CREATE TABLE service_types (code TEXT PRIMARY KEY, payer_scope TEXT NOT NULL CHECK (payer_scope IN ('HOUSE','EARTH','CORPORATION')), daily_price_units BIGINT NOT NULL CHECK (daily_price_units >= 0), allocation_priority INTEGER NOT NULL CHECK (allocation_priority >= 0), rules_version TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED')));
CREATE TABLE house_need_assessments (house_id TEXT NOT NULL REFERENCES houses(id), game_day BIGINT NOT NULL, need_code TEXT NOT NULL REFERENCES need_rules(need_code), demand_units BIGINT NOT NULL CHECK (demand_units >= 0), available_units BIGINT NOT NULL CHECK (available_units >= 0), allocated_units BIGINT NOT NULL CHECK (allocated_units >= 0), shortfall_units BIGINT NOT NULL CHECK (shortfall_units >= 0), risk_level TEXT NOT NULL CHECK (risk_level IN ('NORMAL','WATCH','CRITICAL')), rules_version TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (house_id, game_day, need_code), CHECK (allocated_units <= demand_units), CHECK (shortfall_units = demand_units - allocated_units));
CREATE TABLE service_allocations (id TEXT PRIMARY KEY, house_id TEXT NOT NULL REFERENCES houses(id), territory_id TEXT NOT NULL REFERENCES territories(id), service_code TEXT NOT NULL REFERENCES service_types(code), provider_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), payer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), game_day BIGINT NOT NULL, capacity_units BIGINT NOT NULL CHECK (capacity_units > 0), allocated_units BIGINT NOT NULL CHECK (allocated_units > 0), price_units BIGINT NOT NULL CHECK (price_units >= 0), economic_transaction_id BIGINT REFERENCES economic_transactions(id), correlation_id TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE (house_id, service_code, game_day, provider_economic_id));
CREATE INDEX house_need_assessments_day_idx ON house_need_assessments (game_day, house_id);
CREATE INDEX service_allocations_provider_day_idx ON service_allocations (provider_economic_id, game_day);
CREATE TABLE house_operating_policies (id TEXT PRIMARY KEY, house_id TEXT NOT NULL REFERENCES houses(id), policy_type TEXT NOT NULL CHECK (policy_type IN ('OPERATING','INVENTORY_RESERVE','MARKET_STANDING')), version INTEGER NOT NULL CHECK (version > 0), effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1), status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','PAUSED','SUPERSEDED')), operating_mode TEXT NOT NULL DEFAULT 'BALANCED' CHECK (operating_mode IN ('CONSERVATIVE','BALANCED','GROWTH','CUSTOM')), daily_spend_cap_units BIGINT NOT NULL DEFAULT 0 CHECK (daily_spend_cap_units >= 0), reserve_floor_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(reserve_floor_units) = 'object'), max_input_price_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(max_input_price_units) = 'object'), min_sale_price_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(min_sale_price_units) = 'object'), procurement_quantity_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(procurement_quantity_units) = 'object'), rules_version TEXT NOT NULL, correlation_id TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE (house_id, policy_type, version));
CREATE INDEX house_operating_policies_active_idx ON house_operating_policies (house_id, policy_type, effective_from_game_day DESC) WHERE status = 'ACTIVE';
CREATE TABLE policy_execution_log (id BIGSERIAL PRIMARY KEY, policy_id TEXT NOT NULL REFERENCES house_operating_policies(id), house_id TEXT NOT NULL REFERENCES houses(id), game_day BIGINT NOT NULL, action_type TEXT NOT NULL, action_correlation_id TEXT NOT NULL UNIQUE, decision JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX policy_execution_log_house_day_idx ON policy_execution_log (house_id, game_day DESC);
CREATE INDEX economic_entries_transaction_idx ON economic_entries(transaction_id);
CREATE UNIQUE INDEX auth_email_deliveries_correlation_uq ON auth_email_deliveries(correlation_id);
CREATE INDEX auth_email_deliveries_account_idx ON auth_email_deliveries(account_id, created_at);
CREATE INDEX market_orders_open_idx ON market_orders(instrument_id, status, side, limit_price_units, created_at);
CREATE INDEX market_fills_orders_idx ON market_fills(buy_order_id, sell_order_id);
CREATE INDEX tax_obligations_taxpayer_idx ON tax_obligations(taxpayer_economic_id, status);
CREATE INDEX financial_obligations_debtor_status_idx ON financial_obligations(debtor_economic_id, status, due_game_day);
CREATE INDEX financial_obligations_creditor_idx ON financial_obligations(creditor_economic_id, status, due_game_day);
CREATE INDEX outbox_pending_idx ON event_outbox(status, created_at);

-- =====================================================
-- SECTION 2: FUNCTIONS
-- =====================================================

-- Final baseline database logic only. Compatibility transfer functions are excluded.

CREATE OR REPLACE FUNCTION earth_validate_economic_account_capability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_asset_kind TEXT;
BEGIN
  SELECT owner_type INTO v_owner_type
    FROM owner_registry
   WHERE economic_id = NEW.owner_economic_id;
  IF v_owner_type IS NULL THEN
    RAISE EXCEPTION 'economic account owner does not exist: %', NEW.owner_economic_id;
  END IF;

  SELECT asset_kind INTO v_asset_kind
    FROM economic_assets
   WHERE id = NEW.asset_id;
  IF v_asset_kind IS NULL THEN
    RAISE EXCEPTION 'economic account asset does not exist: %', NEW.asset_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM economic_account_policies p
     WHERE p.owner_type = v_owner_type
       AND p.account_type = NEW.account_type
       AND (p.allowed_asset_kind = v_asset_kind OR p.allowed_asset_kind = 'ANY')
  ) THEN
    RAISE EXCEPTION 'economic account capability denied: owner_type=%, account_type=%, asset_kind=%',
      v_owner_type, NEW.account_type, v_asset_kind;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER economic_accounts_capability_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, asset_id, account_type ON economic_accounts
FOR EACH ROW EXECUTE FUNCTION earth_validate_economic_account_capability();

CREATE OR REPLACE FUNCTION earth_validate_market_order_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_asset_kind TEXT;
BEGIN
  SELECT o.owner_type, a.asset_kind
    INTO v_owner_type, v_asset_kind
    FROM owner_registry o
    JOIN economic_assets a ON a.id = (SELECT asset_id FROM market_instruments WHERE id = NEW.instrument_id)
   WHERE o.economic_id = NEW.owner_economic_id;
  IF v_owner_type <> 'HOUSE' THEN
    RAISE EXCEPTION 'market orders are House-only';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER market_orders_house_owner_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, instrument_id ON market_orders
FOR EACH ROW EXECUTE FUNCTION earth_validate_market_order_owner();

CREATE OR REPLACE FUNCTION earth_provision_house_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'HOUSE' THEN
    RAISE EXCEPTION 'House economy provisioning requires a HOUSE owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'WALLET' FROM economic_assets WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'INVENTORY' FROM economic_assets WHERE asset_kind = 'RESOURCE'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id
     AND ((account_type = 'WALLET' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT'))
       OR (account_type = 'INVENTORY' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'RESOURCE')));
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_corporation_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'CORPORATION' THEN
    RAISE EXCEPTION 'Corporation economy provisioning requires a CORPORATION owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('TREASURY'::TEXT), ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_earth_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'EARTH' THEN
    RAISE EXCEPTION 'EARTH economy provisioning requires an EARTH owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('TREASURY'::TEXT), ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_bank_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'BANK' THEN
    RAISE EXCEPTION 'Bank economy provisioning requires a BANK owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_settlement_watermark(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE SQL STABLE AS $$
  SELECT COALESCE(MAX(game_day) FILTER (WHERE status IN ('completed', 'baseline')), 0)::BIGINT
    FROM daily_settlement_runs
   WHERE game_day <= p_game_day;
$$;

CREATE OR REPLACE FUNCTION earth_claim_settlement_day(
  p_game_day BIGINT, p_worker_id TEXT, p_lease_seconds INTEGER DEFAULT 30
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  WITH candidate AS (
    SELECT current.id
      FROM daily_settlement_phase_runs current
     WHERE current.game_day = p_game_day
       AND (current.status = 'pending' OR (current.status = 'running' AND current.lease_expires_at < CURRENT_TIMESTAMP))
       AND NOT EXISTS (
         SELECT 1 FROM daily_settlement_phase_runs prior
          WHERE prior.game_day = current.game_day AND prior.phase_order < current.phase_order AND prior.status <> 'completed'
       )
     ORDER BY current.phase_order, current.shard FOR UPDATE SKIP LOCKED LIMIT 1
  )
  UPDATE daily_settlement_phase_runs work
     SET status = 'running', lease_owner = p_worker_id,
         lease_expires_at = CURRENT_TIMESTAMP + (p_lease_seconds::TEXT || ' seconds')::INTERVAL,
         attempt_count = work.attempt_count + 1,
         started_at = COALESCE(work.started_at, CURRENT_TIMESTAMP), updated_at = CURRENT_TIMESTAMP
    FROM candidate WHERE work.id = candidate.id
  RETURNING work.id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_heartbeat_settlement_day(
  p_game_day BIGINT, p_worker_id TEXT, p_phase_id TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_runs
     SET current_phase = p_phase_id, lease_owner = p_worker_id,
         lease_heartbeat_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running';
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_complete_settlement_day(p_game_day BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_runs
     SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
         current_phase = NULL, lease_owner = NULL,
         lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running'
     AND NOT EXISTS (SELECT 1 FROM daily_settlement_phase_runs WHERE game_day = p_game_day AND status <> 'completed');
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_fail_settlement_day(
  p_work_id BIGINT, p_worker_id TEXT, p_error_message TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_phase_runs
     SET status = CASE WHEN attempt_count >= 5 THEN 'failed' ELSE 'pending' END,
         lease_owner = NULL, lease_expires_at = NULL,
         error_message = LEFT(p_error_message, 1000), updated_at = CURRENT_TIMESTAMP
   WHERE id = p_work_id AND status = 'running' AND lease_owner = p_worker_id;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_begin_economic_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  IF NULLIF(TRIM(p_transaction_kind), '') IS NULL OR NULLIF(TRIM(p_source_type), '') IS NULL THEN
    RAISE EXCEPTION 'economic transaction kind and source type are required';
  END IF;
  INSERT INTO economic_transactions(correlation_id, game_day, game_minute, transaction_kind, source_type, source_id, rules_version)
  VALUES (p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version)
  ON CONFLICT (correlation_id) DO UPDATE SET correlation_id = EXCLUDED.correlation_id
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT, p_entries JSONB
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_id BIGINT;
  v_entry JSONB;
  v_account_asset_id INTEGER;
  v_entry_asset_kind TEXT;
  v_semantic_class TEXT;
  v_asset_kind TEXT;
  v_asset_id INTEGER;
  v_asset_total BIGINT;
BEGIN
  v_id := earth_begin_economic_transaction(p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version);
  IF EXISTS (SELECT 1 FROM economic_entries WHERE transaction_id = v_id) THEN RETURN v_id; END IF;
  IF COALESCE(jsonb_array_length(p_entries), 0) = 0 THEN RAISE EXCEPTION 'economic transaction must contain entries'; END IF;

  SELECT COALESCE(k.semantic_class, 'ASSET_TRANSFER'), COALESCE(k.asset_kind, 'ANY')
    INTO v_semantic_class, v_asset_kind
    FROM (SELECT 1) seed
    LEFT JOIN economic_transaction_kinds k ON k.code = p_transaction_kind;

  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    SELECT asset_id INTO v_account_asset_id FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT;
    IF v_account_asset_id IS NULL THEN
      RAISE EXCEPTION 'economic transaction account does not exist: %', v_entry->>'account_id';
    END IF;
    IF v_account_asset_id <> (v_entry->>'asset_id')::INTEGER THEN
      RAISE EXCEPTION 'economic entry asset does not match account asset: account=%, entry_asset=%', v_entry->>'account_id', v_entry->>'asset_id';
    END IF;
    SELECT asset_kind INTO v_entry_asset_kind FROM economic_assets WHERE id = (v_entry->>'asset_id')::INTEGER;
    IF v_entry_asset_kind IS NULL THEN
      RAISE EXCEPTION 'economic transaction asset does not exist: %', v_entry->>'asset_id';
    END IF;
    IF v_asset_kind <> 'ANY' AND v_entry_asset_kind <> v_asset_kind THEN
      RAISE EXCEPTION 'transaction semantic % only accepts % assets', v_semantic_class, v_asset_kind;
    END IF;
  END LOOP;

  FOR v_asset_id, v_asset_total IN
    SELECT (value->>'asset_id')::INTEGER, SUM((value->>'delta_units')::BIGINT)
      FROM jsonb_array_elements(p_entries)
     GROUP BY (value->>'asset_id')::INTEGER
  LOOP
    IF v_semantic_class = 'ASSET_TRANSFER' AND v_asset_total <> 0 THEN
      RAISE EXCEPTION 'asset transfer is not balanced for asset %', v_asset_id;
    ELSIF v_semantic_class = 'CREDIT_ISSUANCE' AND v_asset_total <= 0 THEN
      RAISE EXCEPTION 'CREDIT issuance must create a positive CREDIT amount for asset %', v_asset_id;
    ELSIF v_semantic_class = 'CREDIT_RETIREMENT' AND v_asset_total >= 0 THEN
      RAISE EXCEPTION 'CREDIT retirement must destroy a positive CREDIT amount for asset %', v_asset_id;
    ELSIF v_semantic_class IN ('RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION') AND v_asset_total <> 0 THEN
      RAISE EXCEPTION 'resource production/consumption must balance against its dedicated system account for asset %', v_asset_id;
    END IF;
  END LOOP;

  IF v_semantic_class = 'CREDIT_ISSUANCE' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) WHERE (value->>'delta_units')::BIGINT <= 0
  ) THEN
    RAISE EXCEPTION 'CREDIT issuance entries must all be positive';
  ELSIF v_semantic_class = 'CREDIT_RETIREMENT' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) WHERE (value->>'delta_units')::BIGINT >= 0
  ) THEN
    RAISE EXCEPTION 'CREDIT retirement entries must all be negative';
  END IF;
  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    INSERT INTO economic_entries(transaction_id, account_id, delta_units, asset_id)
    VALUES (v_id, (v_entry->>'account_id')::BIGINT, (v_entry->>'delta_units')::BIGINT, (v_entry->>'asset_id')::INTEGER);
    UPDATE economic_accounts SET balance_units = balance_units + (v_entry->>'delta_units')::BIGINT WHERE id = (v_entry->>'account_id')::BIGINT;
    IF EXISTS (SELECT 1 FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT AND balance_units < 0) THEN RAISE EXCEPTION 'economic account would become negative'; END IF;
  END LOOP;
  RETURN v_id;
END;
$$;

-- Starter packages are the only player-facing issuance in the baseline. They
-- are explicit, auditable and idempotent; ordinary transfers remain balanced.
CREATE OR REPLACE FUNCTION earth_issue_starter_package(
  p_correlation_id TEXT, p_game_day BIGINT, p_house_economic_id TEXT,
  p_asset_id INTEGER, p_amount_units BIGINT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_target_account BIGINT; v_source_account BIGINT; v_tx BIGINT;
BEGIN
  IF p_amount_units <= 0 THEN RAISE EXCEPTION 'starter issuance amount must be positive'; END IF;
  SELECT id INTO v_target_account FROM economic_accounts
   WHERE owner_economic_id = p_house_economic_id AND asset_id = p_asset_id
     AND account_type = CASE WHEN p_asset_id = 1 THEN 'WALLET' ELSE 'INVENTORY' END
     AND status = 'ACTIVE' FOR UPDATE;
  IF v_target_account IS NULL THEN RAISE EXCEPTION 'starter account is not provisioned'; END IF;
  IF p_asset_id = 1 THEN
    v_tx := earth_post_transaction(
      p_correlation_id, p_game_day, 0, 'CREDIT_ISSUANCE', 'SYSTEM_ISSUANCE',
      p_house_economic_id, 'starter-package-v1',
      jsonb_build_array(jsonb_build_object(
        'account_id', v_target_account, 'asset_id', p_asset_id, 'delta_units', p_amount_units
      ))
    );
  ELSE
    SELECT a.id INTO v_source_account
      FROM economic_accounts a
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id
     WHERE o.economic_id = 'ECON-RESOURCE-PRODUCTION'
       AND a.asset_id = p_asset_id AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'
     FOR UPDATE;
    IF v_source_account IS NULL THEN RAISE EXCEPTION 'resource production account is not provisioned'; END IF;
    v_tx := earth_post_transaction(
      p_correlation_id, p_game_day, 0, 'RESOURCE_PRODUCTION', 'SYSTEM_PRODUCTION',
      p_house_economic_id, 'starter-package-v1',
      jsonb_build_array(
        jsonb_build_object('account_id', v_source_account, 'asset_id', p_asset_id, 'delta_units', -p_amount_units),
        jsonb_build_object('account_id', v_target_account, 'asset_id', p_asset_id, 'delta_units', p_amount_units)
      )
    );
  END IF;
  RETURN v_tx;
END;
$$;

CREATE OR REPLACE FUNCTION earth_daily_asset_flow(p_game_day BIGINT)
RETURNS TABLE(asset_code TEXT, asset_kind TEXT, credit_created BIGINT, credit_destroyed BIGINT, resource_produced BIGINT, resource_consumed BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT a.code, a.asset_kind,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'CREDIT_ISSUANCE' AND e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'CREDIT_RETIREMENT' AND e.delta_units < 0 THEN ABS(e.delta_units) ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'RESOURCE_PRODUCTION' AND e.delta_units > 0 AND o.owner_type <> 'SYSTEM' THEN e.delta_units ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0 AND o.owner_type <> 'SYSTEM' THEN ABS(e.delta_units) ELSE 0 END), 0)::BIGINT
    FROM economic_assets a
    LEFT JOIN economic_entries e ON e.asset_id = a.id
    LEFT JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = p_game_day
    LEFT JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
    LEFT JOIN economic_accounts ea ON ea.id = e.account_id
    LEFT JOIN owner_registry o ON o.economic_id = ea.owner_economic_id
   GROUP BY a.id, a.code, a.asset_kind
   ORDER BY a.id;
$$;

CREATE OR REPLACE FUNCTION earth_assert_baseline_integrity() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM economic_accounts a
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      JOIN economic_assets e ON e.id = a.asset_id
     WHERE NOT EXISTS (
       SELECT 1 FROM economic_account_policies p
        WHERE p.owner_type = o.owner_type
          AND p.account_type = a.account_type
          AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY')
     )
  ) THEN RAISE EXCEPTION 'economic account capability invariant failed'; END IF;
  IF EXISTS (
    SELECT 1
      FROM market_orders m
      JOIN owner_registry o ON o.economic_id = m.owner_economic_id
      JOIN market_instruments i ON i.id = m.instrument_id
      JOIN economic_assets a ON a.id = i.asset_id
     WHERE o.owner_type <> 'HOUSE'
  ) THEN RAISE EXCEPTION 'market owner invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units) THEN RAISE EXCEPTION 'market order quantity invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM institution_budget_lines WHERE authorized_units < committed_units + spent_units) THEN RAISE EXCEPTION 'budget authority invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM humans h JOIN houses x ON x.current_human_id = h.id WHERE h.status <> 'ACTIVE') THEN RAISE EXCEPTION 'House current Human invariant failed'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_game_day_from_total_minutes(p_total_minutes BIGINT)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT FLOOR(p_total_minutes / 1440)::BIGINT;
$$;

CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE(game_day BIGINT, game_minute INTEGER, total_game_minutes BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT game_day, game_minute, game_day * 1440 + game_minute
    FROM world_state WHERE id = 'WORLD';
$$;

CREATE OR REPLACE FUNCTION earth_advance_world_clock(p_minutes INTEGER)
RETURNS TABLE(game_day BIGINT, game_minute INTEGER, advanced_minutes INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
  IF p_minutes IS NULL OR p_minutes < 1 OR p_minutes > 1440 THEN
    RAISE EXCEPTION 'World advancement must be between 1 and 1,440 game minutes';
  END IF;
  RETURN QUERY
  UPDATE world_state
     SET game_day = world_state.game_day + ((world_state.game_minute + p_minutes) / 1440),
         game_minute = (world_state.game_minute + p_minutes) % 1440
   WHERE world_state.id = 'WORLD'
   RETURNING world_state.game_day, world_state.game_minute, p_minutes;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_settlement_batch(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_source_type TEXT, p_source_id TEXT, p_rules_version TEXT, p_effects JSONB
) RETURNS TABLE(transaction_id BIGINT, created BOOLEAN)
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  v_id := earth_post_transaction(p_correlation_id, p_game_day, p_game_minute, 'SETTLEMENT', p_source_type, p_source_id, p_rules_version, p_effects);
  RETURN QUERY SELECT v_id, TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION earth_refresh_territory_capacity(
  p_territory_id TEXT,
  p_game_day BIGINT
)
RETURNS territory_capacity_state
LANGUAGE plpgsql
AS $$
DECLARE result territory_capacity_state;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM territories WHERE id = p_territory_id) THEN
    RAISE EXCEPTION 'Territory not found';
  END IF;

  INSERT INTO territory_capacity_state (
    territory_id, game_day, active_house_count, house_capacity, population_capacity,
    private_slot_capacity, public_slot_capacity, private_slots_used, public_slots_used,
    housing_capacity, health_capacity, energy_capacity, connectivity_capacity,
    service_capacity, updated_at
  )
  SELECT
    p_territory_id,
    p_game_day,
    (SELECT COUNT(*)::INTEGER FROM house_affiliations ha
      WHERE ha.primary_territory_id = p_territory_id AND ha.status = 'ACTIVE'),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code IN ('POPULATION_CAPACITY', 'HOUSE_CAPACITY')), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code IN ('POPULATION_CAPACITY', 'HOUSE_CAPACITY')), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'PRIVATE_SLOTS'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'PUBLIC_SLOTS'), 0),
    COALESCE((SELECT SUM(b.slot_footprint)::BIGINT FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND o.owner_type = 'HOUSE'), 0),
    COALESCE((SELECT SUM(b.slot_footprint)::BIGINT FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND o.owner_type = 'CORPORATION'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'HOUSING_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'HEALTH_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'ENERGY_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'CONNECTIVITY_CAPACITY'), 0),
    COALESCE((SELECT jsonb_object_agg(service_key, service_total) FROM (
      SELECT COALESCE(NULLIF(bc.service_type, ''), 'UNSPECIFIED') AS service_key,
             SUM(bc.service_capacity_units)::BIGINT AS service_total
        FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
       WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND bc.service_capacity_units > 0
       GROUP BY COALESCE(NULLIF(bc.service_type, ''), 'UNSPECIFIED')
    ) services), '{}'::jsonb),
    now()
  FROM buildings b
  LEFT JOIN building_catalog_effects e ON e.catalog_id = b.catalog_id
  WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE'
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_validate_building_ownership()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  owner_kind TEXT;
  ownership_scope TEXT;
  territory_corporation_id TEXT;
BEGIN
  SELECT owner_type INTO owner_kind FROM owner_registry WHERE economic_id = NEW.owner_economic_id;
  SELECT bc.ownership_scope INTO ownership_scope FROM building_catalog bc WHERE bc.id = NEW.catalog_id;
  SELECT t.corporation_id INTO territory_corporation_id FROM territories t WHERE t.id = NEW.territory_id;

  IF owner_kind IS NULL OR ownership_scope IS NULL OR territory_corporation_id IS NULL THEN
    RAISE EXCEPTION 'Building owner, blueprint, and Territory must exist';
  END IF;
  IF ownership_scope = 'PUBLIC' AND owner_kind <> 'CORPORATION' THEN
    RAISE EXCEPTION 'Public infrastructure must be Corporation-owned';
  END IF;
  IF ownership_scope = 'PRIVATE' AND owner_kind <> 'HOUSE' THEN
    RAISE EXCEPTION 'Private buildings must be House-owned';
  END IF;
  IF ownership_scope = 'PUBLIC' AND NOT EXISTS (
    SELECT 1 FROM owner_registry o
    WHERE o.id = territory_corporation_id AND o.economic_id = NEW.owner_economic_id AND o.owner_type = 'CORPORATION'
  ) THEN
    RAISE EXCEPTION 'Public infrastructure owner must be the Territory Corporation';
  END IF;
  IF ownership_scope = 'PRIVATE' AND NOT EXISTS (
    SELECT 1 FROM owner_registry o
    JOIN house_affiliations ha ON ha.house_id = o.id
    WHERE o.economic_id = NEW.owner_economic_id AND o.owner_type = 'HOUSE'
      AND ha.corporation_id = territory_corporation_id AND ha.status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'Private building owner must be an active House in the Territory Corporation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER buildings_ownership_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, territory_id, catalog_id ON buildings
FOR EACH ROW EXECUTE FUNCTION earth_validate_building_ownership();

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'negative_economic_balances', COUNT(*) FROM economic_accounts WHERE balance_units < 0
  UNION ALL SELECT 'invalid_economic_account_capabilities', COUNT(*)
    FROM economic_accounts a
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_assets e ON e.id = a.asset_id
   WHERE NOT EXISTS (
     SELECT 1 FROM economic_account_policies p
      WHERE p.owner_type = o.owner_type
        AND p.account_type = a.account_type
        AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY')
   )
  UNION ALL SELECT 'invalid_market_order_owners', COUNT(*)
    FROM market_orders m
    JOIN owner_registry o ON o.economic_id = m.owner_economic_id
    JOIN market_instruments i ON i.id = m.instrument_id
    JOIN economic_assets e ON e.id = i.asset_id
   WHERE o.owner_type <> 'HOUSE'
  UNION ALL SELECT 'invalid_house_current_human', COUNT(*) FROM houses h JOIN humans x ON x.id = h.current_human_id WHERE x.status <> 'ACTIVE'
  UNION ALL SELECT 'invalid_market_orders', COUNT(*) FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units
  UNION ALL SELECT 'invalid_budget_authority', COUNT(*) FROM institution_budget_lines WHERE authorized_units < committed_units + spent_units;
$$;

CREATE OR REPLACE FUNCTION earth_market_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'invalid_market_orders', COUNT(*) FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units;
$$;

-- Tax amendments are serialized by rule lineage and always close the
-- previous open interval before the successor becomes effective.
CREATE OR REPLACE FUNCTION earth_create_tax_rule_version(
  p_tax_rule_id TEXT,
  p_scope TEXT,
  p_category TEXT,
  p_rate_bps INTEGER,
  p_tax_base_definition TEXT,
  p_beneficiary_economic_id TEXT,
  p_effective_from_game_day BIGINT,
  p_authorization_proposal_id TEXT
) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  v_version INTEGER;
  v_id TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_tax_rule_id, 0));
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_version
    FROM tax_rule_versions
   WHERE tax_rule_id = p_tax_rule_id;
  UPDATE tax_rule_versions
     SET effective_to_game_day = p_effective_from_game_day - 1
   WHERE tax_rule_id = p_tax_rule_id
     AND effective_to_game_day IS NULL;
  v_id := p_tax_rule_id || '-V' || v_version::TEXT;
  INSERT INTO tax_rule_versions (
    id, tax_rule_id, scope, category, version, effective_from_game_day,
    rate_bps, tax_base_definition, beneficiary_economic_id, authorization_proposal_id
  ) VALUES (
    v_id, p_tax_rule_id, p_scope, p_category, v_version, p_effective_from_game_day,
    p_rate_bps, p_tax_base_definition, p_beneficiary_economic_id, p_authorization_proposal_id
  );
  RETURN v_id;
END;
$$;
-- Technology/IP V2 functions.
CREATE OR REPLACE FUNCTION earth_technology_is_patentable(p_technology_id TEXT)
RETURNS BOOLEAN LANGUAGE SQL STABLE AS $$
  SELECT COALESCE((SELECT patentable FROM technology_catalog
    WHERE id = p_technology_id OR code = p_technology_id
    ORDER BY effective_from_game_day DESC, definition_version DESC LIMIT 1), FALSE);
$$;

CREATE OR REPLACE FUNCTION earth_resolve_corporation_technology_access(
  p_corporation_economic_id TEXT, p_technology_id TEXT, p_game_day BIGINT
) RETURNS TABLE(has_access BOOLEAN, access_reason TEXT, source_id TEXT)
LANGUAGE SQL STABLE AS $$
  SELECT TRUE, a.access_source, a.source_id
  FROM corporation_technology_access a
  WHERE a.corporation_economic_id = p_corporation_economic_id
    AND a.technology_id = p_technology_id AND a.status = 'ACTIVE'
    AND a.effective_from_game_day <= p_game_day
    AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
  ORDER BY CASE a.access_source WHEN 'RESEARCHED' THEN 1 WHEN 'LICENSED' THEN 2 ELSE 3 END
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION earth_assert_technology_research_allowed(p_technology_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM technology_catalog WHERE id = p_technology_id AND status = 'ACTIVE' AND effective_from_game_day <= p_game_day AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)) THEN
    RAISE EXCEPTION 'Technology catalog entry is not active for research';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_assert_technology_prerequisites_met(p_corporation_economic_id TEXT, p_technology_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_corporation_economic_id IS NULL OR p_technology_id IS NULL OR p_game_day < 0 THEN
    RAISE EXCEPTION 'Invalid technology research prerequisites';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_corporation_technology_access(
  p_corporation_economic_id TEXT, p_technology_id TEXT, p_access_source TEXT,
  p_source_id TEXT, p_effective_from_game_day BIGINT, p_effective_to_game_day BIGINT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_access_source NOT IN ('RESEARCHED','LICENSED','GRANTED') THEN RAISE EXCEPTION 'Invalid technology access source'; END IF;
  INSERT INTO corporation_technology_access (corporation_economic_id, technology_id, access_source, source_id, effective_from_game_day, effective_to_game_day, status)
  VALUES (p_corporation_economic_id, p_technology_id, p_access_source, p_source_id, p_effective_from_game_day, p_effective_to_game_day, 'ACTIVE')
  ON CONFLICT (corporation_economic_id, technology_id) DO UPDATE SET access_source = EXCLUDED.access_source, source_id = EXCLUDED.source_id, effective_from_game_day = EXCLUDED.effective_from_game_day, effective_to_game_day = EXCLUDED.effective_to_game_day, status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_completed_technology_patents(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE technology_patents SET status = 'EXPIRED' WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;
  INSERT INTO technology_patents (id, technology_id, owner_economic_id, granted_game_day, exclusive_through_game_day, status, granting_project_id)
  SELECT 'PATENT-' || p.target_id || '-' || p.id, p.target_id, p.corporation_economic_id, p.completed_game_day,
    p.completed_game_day + t.patent_exclusivity_days - 1, 'ACTIVE', p.id
  FROM corporation_research_projects p JOIN technology_catalog t ON t.id = p.target_id
  WHERE p.target_type = 'TECHNOLOGY' AND p.status = 'COMPLETED' AND p.completed_game_day = p_game_day
    AND t.patentable AND t.patent_exclusivity_days > 0 AND NOT EXISTS (SELECT 1 FROM technology_patents x WHERE x.technology_id = p.target_id AND x.status = 'ACTIVE')
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_finalize_technology_public_domain(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE technology_patents SET status = 'EXPIRED' WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;
  INSERT INTO technology_public_domain (technology_id, effective_from_game_day, source_patent_id)
  SELECT p.technology_id, p.exclusive_through_game_day + 1, p.id FROM technology_patents p
  WHERE p.status = 'EXPIRED' AND p.exclusive_through_game_day < p_game_day ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_refresh_house_daily_statements(p_game_day BIGINT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
  WITH owners AS (
    SELECT h.id AS house_id, o.economic_id FROM houses h
    JOIN owner_registry o ON o.id = h.id AND o.owner_type = 'HOUSE'
  ), daily_delta AS (
    SELECT o.house_id, a.asset_id, SUM(e.delta_units)::BIGINT AS delta_units
    FROM owners o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
    JOIN economic_entries e ON e.account_id = a.id
    JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = p_game_day
    GROUP BY o.house_id, a.asset_id
  ), balances AS (
    SELECT o.house_id, asset.code, COALESCE(SUM(a.balance_units), 0)::BIGINT AS closing_units,
      COALESCE(SUM(a.balance_units), 0)::BIGINT - COALESCE(SUM(d.delta_units), 0)::BIGINT AS opening_units
    FROM owners o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.status = 'ACTIVE'
    JOIN economic_assets asset ON asset.id = a.asset_id
    LEFT JOIN daily_delta d ON d.house_id = o.house_id AND d.asset_id = a.asset_id
    GROUP BY o.house_id, asset.code
  ), balance_json AS (
    SELECT house_id, jsonb_object_agg(code, opening_units::TEXT ORDER BY code) AS opening_assets,
      jsonb_object_agg(code, closing_units::TEXT ORDER BY code) AS closing_assets FROM balances GROUP BY house_id
  ), flow_json AS (
    SELECT o.house_id,
      COALESCE(jsonb_object_agg(asset.code, flow.produced::TEXT ORDER BY asset.code) FILTER (WHERE flow.produced > 0), '{}'::jsonb) AS production,
      COALESCE(jsonb_object_agg(asset.code, flow.consumed::TEXT ORDER BY asset.code) FILTER (WHERE flow.consumed > 0), '{}'::jsonb) AS consumption
    FROM owners o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
    JOIN economic_assets asset ON asset.id = a.asset_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(SUM(e.delta_units) FILTER (WHERE t.transaction_kind = 'RESOURCE_PRODUCTION' AND e.delta_units > 0), 0)::BIGINT AS produced,
        COALESCE(SUM(-e.delta_units) FILTER (WHERE t.transaction_kind = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0), 0)::BIGINT AS consumed
      FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id
      WHERE e.account_id = a.id AND t.game_day = p_game_day
    ) flow ON TRUE GROUP BY o.house_id
  ), market_json AS (
    SELECT owner.house_id, jsonb_object_agg(m.symbol, jsonb_build_object('purchases', m.purchases::TEXT, 'sales', m.sales::TEXT, 'volume', m.volume::TEXT, 'fees', m.fees::TEXT) ORDER BY m.symbol) AS market_activity
    FROM owners owner JOIN LATERAL (
      SELECT i.symbol, COALESCE(SUM(f.quantity_units) FILTER (WHERE f.buyer_economic_id = owner.economic_id), 0)::BIGINT AS purchases,
        COALESCE(SUM(f.quantity_units) FILTER (WHERE f.seller_economic_id = owner.economic_id), 0)::BIGINT AS sales,
        COALESCE(SUM(f.quantity_units), 0)::BIGINT AS volume,
        COALESCE(SUM(f.buyer_fee_units) FILTER (WHERE f.buyer_economic_id = owner.economic_id), 0)::BIGINT + COALESCE(SUM(f.seller_fee_units) FILTER (WHERE f.seller_economic_id = owner.economic_id), 0)::BIGINT AS fees
      FROM market_fills f JOIN market_batches b ON b.id = f.batch_id JOIN market_instruments i ON i.id = f.instrument_id
      WHERE b.game_day = p_game_day AND (f.buyer_economic_id = owner.economic_id OR f.seller_economic_id = owner.economic_id) GROUP BY i.symbol
    ) m ON TRUE GROUP BY owner.house_id
  ), obligation_json AS (
    SELECT owner.house_id, jsonb_build_object('taxes', COALESCE(SUM(o.amount_units) FILTER (WHERE o.status IN ('PAID', 'SETTLED')), 0)::TEXT, 'total', COALESCE(SUM(o.amount_units), 0)::TEXT, 'count', COUNT(*)::TEXT) AS obligations
    FROM owners owner LEFT JOIN tax_obligations o ON o.taxpayer_economic_id = owner.economic_id AND o.game_day = p_game_day GROUP BY owner.house_id
  ), exception_json AS (
    SELECT h.id AS house_id, jsonb_build_object('food_shortfall_units', COALESCE(SUM(m.food_shortfall_units), 0)::TEXT, 'unfed_humans', COUNT(*) FILTER (WHERE m.status = 'UNFED')::TEXT) AS exceptions
    FROM houses h LEFT JOIN personal_life_maintenance m ON m.house_id = h.id AND m.game_day = p_game_day GROUP BY h.id
  ), rows_to_write AS (
    SELECT b.house_id, p_game_day, b.opening_assets, b.closing_assets, COALESCE(f.production, '{}'::jsonb), COALESCE(f.consumption, '{}'::jsonb), COALESCE(m.market_activity, '{}'::jsonb), COALESCE(o.obligations, '{}'::jsonb), COALESCE(x.exceptions, '{}'::jsonb), COALESCE((b.closing_assets ->> 'CREDIT')::BIGINT, 0) - COALESCE((b.opening_assets ->> 'CREDIT')::BIGINT, 0)
    FROM balance_json b LEFT JOIN flow_json f USING (house_id) LEFT JOIN market_json m USING (house_id) LEFT JOIN obligation_json o USING (house_id) LEFT JOIN exception_json x USING (house_id)
  )
  INSERT INTO house_daily_statements (house_id, game_day, opening_assets, closing_assets, production, consumption, market_activity, obligations, exceptions, net_credit_units)
  SELECT * FROM rows_to_write
  ON CONFLICT (house_id, game_day) DO UPDATE SET opening_assets = EXCLUDED.opening_assets, closing_assets = EXCLUDED.closing_assets, production = EXCLUDED.production, consumption = EXCLUDED.consumption, market_activity = EXCLUDED.market_activity, obligations = EXCLUDED.obligations, exceptions = EXCLUDED.exceptions, net_credit_units = EXCLUDED.net_credit_units, updated_at = CURRENT_TIMESTAMP;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- =====================================================
-- SECTION 3: REFERENCE DATA
-- =====================================================

INSERT INTO economic_assets(id, code, asset_kind) VALUES
  (1, 'CREDIT', 'CREDIT'),
  (2, 'MATERIAL', 'RESOURCE'),
  (3, 'COMPONENTS', 'RESOURCE'),
  (4, 'ENERGY', 'RESOURCE'),
  (5, 'COMPUTE', 'RESOURCE'),
  (6, 'FOOD', 'RESOURCE');

INSERT INTO economic_transaction_kinds(code, semantic_class, asset_kind, description) VALUES
  ('ASSET_TRANSFER', 'ASSET_TRANSFER', 'ANY', 'Balanced movement of an existing asset between accounts'),
  ('CREDIT_ISSUANCE', 'CREDIT_ISSUANCE', 'CREDIT', 'Creation of CREDIT outside existing account balances'),
  ('CREDIT_RETIREMENT', 'CREDIT_RETIREMENT', 'CREDIT', 'Destruction of CREDIT outside existing account balances'),
  ('RESOURCE_PRODUCTION', 'RESOURCE_PRODUCTION', 'RESOURCE', 'Production of a resource into an economic owner inventory'),
  ('RESOURCE_CONSUMPTION', 'RESOURCE_CONSUMPTION', 'RESOURCE', 'Consumption of a resource from an economic owner inventory'),
  ('STARTER_ISSUANCE', 'CREDIT_ISSUANCE', 'CREDIT', 'Initial CREDIT issuance to a newly registered House'),
  ('SETTLEMENT', 'ASSET_TRANSFER', 'ANY', 'Balanced settlement posting'),
  ('MARKET_TRADE', 'ASSET_TRANSFER', 'ANY', 'Balanced market settlement'),
  ('BUILDING_CONSTRUCTION', 'ASSET_TRANSFER', 'ANY', 'Balanced construction payment'),
  ('CORPORATION_CONTRIBUTION', 'ASSET_TRANSFER', 'CREDIT', 'Balanced House to Corporation contribution'),
  ('CORPORATION_PUBLIC_SPENDING', 'ASSET_TRANSFER', 'CREDIT', 'Balanced Corporation public spending'),
  ('RESEARCH_FUNDING', 'ASSET_TRANSFER', 'CREDIT', 'Balanced research funding'),
  ('SUCCESSION_COST', 'ASSET_TRANSFER', 'CREDIT', 'Balanced House succession cost');

INSERT INTO economic_source_types(code, source_class, description) VALUES
  ('SYSTEM_ISSUANCE', 'SYSTEM', 'System-authorized asset issuance'),
  ('SYSTEM_RETIREMENT', 'SYSTEM', 'System-authorized asset retirement'),
  ('SYSTEM_PRODUCTION', 'SYSTEM', 'System resource production sink/source'),
  ('SYSTEM_CONSUMPTION', 'SYSTEM', 'System resource consumption sink/source'),
  ('HOUSE', 'ACTOR', 'House economic action'),
  ('CORPORATION', 'ACTOR', 'Corporation economic action'),
  ('CORPORATION_RESEARCH', 'ACTOR', 'Corporation research action'),
  ('BANK', 'ACTOR', 'Bank economic action'),
  ('MARKET', 'MARKET', 'Market clearing action'),
  ('PROPOSAL', 'GOVERNANCE', 'Governance-authorized action'),
  ('INTERACTIVE', 'INTERACTIVE', 'Interactive user action'),
  ('SETTLEMENT', 'SETTLEMENT', 'Daily settlement action');

INSERT INTO economic_account_types(code) VALUES
  ('WALLET'), ('TREASURY'), ('OPERATIONS'), ('RESERVE'),
  ('INVENTORY'), ('MARKET_ESCROW'), ('SYSTEM_ACCOUNT');

INSERT INTO economic_account_policies(owner_type, account_type, allowed_asset_kind, player_visible) VALUES
  ('HOUSE', 'WALLET', 'CREDIT', TRUE),
  ('HOUSE', 'INVENTORY', 'RESOURCE', TRUE),
  ('HOUSE', 'MARKET_ESCROW', 'ANY', TRUE),
  ('CORPORATION', 'TREASURY', 'CREDIT', TRUE),
  ('CORPORATION', 'OPERATIONS', 'CREDIT', TRUE),
  ('CORPORATION', 'RESERVE', 'CREDIT', TRUE),
  ('EARTH', 'TREASURY', 'CREDIT', TRUE),
  ('EARTH', 'OPERATIONS', 'CREDIT', TRUE),
  ('EARTH', 'RESERVE', 'CREDIT', TRUE),
  ('BANK', 'OPERATIONS', 'CREDIT', TRUE),
  ('BANK', 'RESERVE', 'CREDIT', TRUE),
  ('SYSTEM', 'SYSTEM_ACCOUNT', 'ANY', FALSE);

INSERT INTO budget_categories(id, institution_kind, category_code, spending_class, priority) VALUES
  ('BUDGET-DEBT', 'CORPORATION', 'DEBT_SERVICE', 'MANDATORY', 1),
  ('BUDGET-ESSENTIAL', 'CORPORATION', 'ESSENTIAL_SERVICES', 'MANDATORY', 2),
  ('BUDGET-OPS', 'CORPORATION', 'OPERATIONS', 'MANDATORY', 2),
  ('BUDGET-RESEARCH', 'CORPORATION', 'RESEARCH', 'DISCRETIONARY', 5),
  ('BUDGET-DIVIDENDS', 'CORPORATION', 'DIVIDENDS', 'DISCRETIONARY', 9);

INSERT INTO fiscal_periods(id, period_type, start_game_day, end_game_day, status)
VALUES ('FISCAL-YEAR-1', 'YEAR', 1, 365, 'ACTIVE');

INSERT INTO constitutional_rules (id, part_number, rule_number, title, description, default_value, permitted_values, authority)
VALUES
  ('CONST-1-1', 1, '1.1', 'Rule Precedence', 'EARTH constitutional rules are authoritative unless a permitted institutional rule applies.', 'EARTH baseline', 'EARTH, CORPORATION', 'EARTH'),
  ('CONST-2-1', 2, '2.1', 'Daily Economy', 'Economic settlement uses the game day as its fundamental accounting period.', 'Daily', 'Daily only', 'EARTH'),
  ('CONST-3-1', 3, '3.1', 'House Continuity', 'House economic property survives Human succession.', 'Persistent House ownership', 'House', 'EARTH')
ON CONFLICT (id) DO NOTHING;

INSERT INTO economic_policy_rules (code, output_multiplier, cost_multiplier, decay_multiplier, description)
VALUES
  ('balanced', 1.0000, 1.0000, 1.0000, 'Normal production and operating costs'),
  ('high_output', 1.3000, 1.4000, 1.0000, 'Higher output with higher operating cost'),
  ('halted', 0.0000, 0.2000, 1.0000, 'Production halted with minimum operating cost')
ON CONFLICT (code) DO NOTHING;

INSERT INTO tax_governance_rules (scope, category, maximum_rate_bps, allowed_tax_base_definitions, beneficiary_scope, rules_version)
VALUES
  ('EARTH', 'basic_levy', 2000, '["fixed_daily_obligation"]', 'EARTH', 'tax-constitution-v1'),
  ('EARTH', 'personal_income', 3000, '["positive_realized_daily_income"]', 'EARTH', 'tax-constitution-v1'),
  ('EARTH', 'market_transaction', 1000, '["external_market_trade"]', 'EARTH', 'tax-constitution-v1'),
  ('CORPORATION', 'personal_income', 3000, '["positive_realized_daily_income"]', 'CORPORATION', 'tax-constitution-v1'),
  ('CORPORATION', 'corporate_income', 4000, '["positive_realized_daily_taxable_profit"]', 'CORPORATION', 'tax-constitution-v1')
ON CONFLICT (scope, category) DO NOTHING;

INSERT INTO building_catalog (
  id, code, tier, ownership_scope, construction_credit_units, construction_minutes,
  operating_credit_units, resource_input_units, resource_output_units,
  service_type, service_capacity_units, slot_footprint, definition_version
) VALUES
  ('MATERIAL-FAB-T1', 'material_fab_t1', 1, 'PRIVATE', 50000, 1440, 250,
   '{"ENERGY":10}'::jsonb, '{"MATERIAL":100}'::jsonb, NULL, 0, 1, 'building-v1'),
  ('COMPONENT-FAB-T1', 'component_fab_t1', 1, 'PRIVATE', 75000, 2160, 400,
   '{"MATERIAL":25,"ENERGY":20}'::jsonb, '{"COMPONENTS":50}'::jsonb, NULL, 0, 2, 'building-v1'),
  ('ENERGY-PLANT-T1', 'energy_plant_t1', 1, 'PRIVATE', 60000, 1440, 300,
   '{"MATERIAL":10}'::jsonb, '{"ENERGY":120}'::jsonb, NULL, 0, 1, 'building-v1'),
  ('FOOD-FARM-T1', 'food_farm_t1', 1, 'PRIVATE', 45000, 1440, 200,
   '{"ENERGY":8}'::jsonb, '{"FOOD":80}'::jsonb, NULL, 0, 1, 'building-v1'),
  ('HOUSING-T1', 'housing_t1', 1, 'PRIVATE', 80000, 2880, 350,
   '{"ENERGY":15}'::jsonb, '{}'::jsonb, 'HOUSING', 100, 2, 'building-v1')
ON CONFLICT (id) DO NOTHING;

INSERT INTO building_catalog (
  id, code, tier, ownership_scope, construction_credit_units, construction_minutes,
  operating_credit_units, resource_input_units, resource_output_units,
  service_type, service_capacity_units, slot_footprint, definition_version
) VALUES
  ('DISTRICT-MODULE-T1', 'urban-district-module', 1, 'PUBLIC', 100000, 2880, 500,
   '{"MATERIAL":50,"ENERGY":25}'::jsonb, '{}'::jsonb, 'TERRITORY_INFRASTRUCTURE', 0, 1, 'territory-capacity-v1')
ON CONFLICT (id) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
VALUES
  ('DISTRICT-MODULE-T1', 'POPULATION_CAPACITY', 10),
  ('DISTRICT-MODULE-T1', 'PRIVATE_SLOTS', 100),
  ('DISTRICT-MODULE-T1', 'PUBLIC_SLOTS', 20)
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
SELECT id, 'SERVICE_CAPACITY', service_capacity_units
FROM building_catalog
WHERE service_capacity_units > 0
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO technology_catalog (
  id, code, name, patentable, definition_version, research_points_required, credit_cost_units
) VALUES
  ('TECH-AUTOMATION-V1', 'automation', 'Industrial Automation', TRUE, 'tech-v1', 1000, 25000),
  ('TECH-CLEAN-ENERGY-V1', 'clean_energy', 'Clean Energy Systems', TRUE, 'tech-v1', 1200, 30000),
  ('TECH-FOOD-SCIENCE-V1', 'food_science', 'Food Science', FALSE, 'tech-v1', 900, 18000),
  ('TECH-LOGISTICS-V1', 'logistics', 'Logistics Optimization', FALSE, 'tech-v1', 800, 16000),
  ('TECH-RESEARCH-METHODS-V1', 'research_methods', 'Research Methodology', FALSE, 'tech-v1', 1500, 35000)
ON CONFLICT (id) DO NOTHING;

INSERT INTO technology_effects (technology_id, effect_type, target_key, modifier_bps)
VALUES
  ('TECH-AUTOMATION-V1', 'PRODUCTION_OUTPUT', 'ALL', 1000),
  ('TECH-CLEAN-ENERGY-V1', 'ENERGY_INPUT', 'ALL', -1000),
  ('TECH-FOOD-SCIENCE-V1', 'PRODUCTION_OUTPUT', 'FOOD', 1000),
  ('TECH-LOGISTICS-V1', 'SERVICE_CAPACITY', 'ALL', 500),
  ('TECH-RESEARCH-METHODS-V1', 'RESEARCH_CAPACITY', 'ALL', 500)
ON CONFLICT (technology_id, effect_type, target_key) DO NOTHING;

INSERT INTO service_types (code, payer_scope, daily_price_units, allocation_priority, rules_version) VALUES
  ('HOUSING', 'HOUSE', 0, 10, 'services-v1'), ('ENERGY', 'HOUSE', 1, 20, 'services-v1'),
  ('CONNECTIVITY', 'HOUSE', 1, 30, 'services-v1'), ('HEALTH', 'HOUSE', 1, 40, 'services-v1')
ON CONFLICT (code) DO NOTHING;
INSERT INTO need_rules (need_code, service_type_code, demand_units_per_human, critical_threshold_bps, rules_version) VALUES
  ('HOUSING', 'HOUSING', 1, 7500, 'needs-v1'), ('ENERGY', 'ENERGY', 1, 7500, 'needs-v1'),
  ('CONNECTIVITY', 'CONNECTIVITY', 1, 7500, 'needs-v1'), ('HEALTH', 'HEALTH', 1, 7500, 'needs-v1')
ON CONFLICT (need_code) DO NOTHING;

-- =====================================================
-- SECTION 4: INITIAL WORLD
-- =====================================================

INSERT INTO world_state(id, game_day, game_minute, world_seed, status)
VALUES ('WORLD', 1, 0, 'EARTH-GENESIS', 'ACTIVE');

INSERT INTO institutions(id, kind, name) VALUES
  ('EARTH', 'EARTH', 'EARTH UC'),
  ('GLOBAL-BANK', 'BANK', 'Global Bank');

INSERT INTO governance_rules (id, institution_id, name, category, value_json, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days, version, status, effective_from_game_day)
VALUES ('GOV-EARTH-BASELINE-V1', 'EARTH', 'EARTH governance baseline', 'governance', '{"proposal_execution":"governed"}'::jsonb, 0.25, 0.50, 30, 1, 1, 'active', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO owner_registry(id, owner_type, economic_id) VALUES
  ('EARTH', 'EARTH', 'ECON-EARTH-001'),
  ('GLOBAL-BANK', 'BANK', 'ECON-GLOBAL-BANK-001'),
  ('OWNER-MONETARY-ISSUANCE', 'SYSTEM', 'ECON-MONETARY-ISSUANCE'),
  ('OWNER-MONETARY-RETIREMENT', 'SYSTEM', 'ECON-MONETARY-RETIREMENT'),
  ('OWNER-MARKET-CLEARING', 'SYSTEM', 'ECON-MARKET-CLEARING'),
  ('OWNER-RESOURCE-PRODUCTION', 'SYSTEM', 'ECON-RESOURCE-PRODUCTION'),
  ('OWNER-RESOURCE-CONSUMPTION', 'SYSTEM', 'ECON-RESOURCE-CONSUMPTION');

SELECT earth_provision_earth_economy('ECON-EARTH-001');
SELECT earth_provision_bank_economy('ECON-GLOBAL-BANK-001');

INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type) VALUES
  ('ECON-MONETARY-ISSUANCE', 1, 'SYSTEM_ACCOUNT'),
  ('ECON-MONETARY-RETIREMENT', 1, 'SYSTEM_ACCOUNT'),
  ('ECON-MARKET-CLEARING', 1, 'SYSTEM_ACCOUNT'),
  ('ECON-RESOURCE-PRODUCTION', 2, 'SYSTEM_ACCOUNT'),
  ('ECON-RESOURCE-CONSUMPTION', 2, 'SYSTEM_ACCOUNT');

-- Resource consumption and production are recorded against a canonical system
-- inventory owner; these accounts are not player wallets and never represent
-- a second resource authority.
INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
SELECT 'ECON-RESOURCE-PRODUCTION', id, 'SYSTEM_ACCOUNT'
FROM economic_assets
WHERE asset_kind = 'RESOURCE'
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
SELECT 'ECON-RESOURCE-CONSUMPTION', id, 'SYSTEM_ACCOUNT'
FROM economic_assets
WHERE asset_kind = 'RESOURCE'
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

INSERT INTO market_instruments(id, symbol, asset_id, quote_asset_id)
VALUES ('SPOT-MATERIAL', 'MATERIAL', 2, 1), ('SPOT-COMPONENTS', 'COMPONENTS', 3, 1),
       ('SPOT-ENERGY', 'ENERGY', 4, 1), ('SPOT-COMPUTE', 'COMPUTE', 5, 1),
       ('SPOT-FOOD', 'FOOD', 6, 1);

INSERT INTO tax_rule_versions (id, tax_rule_id, scope, category, version, effective_from_game_day, rate_bps, tax_base_definition, beneficiary_economic_id)
VALUES
  ('TAX-BASIC-LEVY-V1', 'TAX-BASIC-LEVY', 'EARTH', 'basic_levy', 1, 1, 0, 'fixed_daily_obligation', 'ECON-EARTH-001'),
  ('TAX-MARKET-TRANSACTION-V1', 'TAX-MARKET-TRANSACTION', 'EARTH', 'market_transaction', 1, 1, 0, 'external_market_trade', 'ECON-EARTH-001');

INSERT INTO daily_settlement_control (id, status)
VALUES ('WORLD', 'awaiting_baseline')
ON CONFLICT (id) DO NOTHING;
