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
CREATE TABLE institutions (id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('OUC','CITY','CORPORATION','BANK')), name TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE cities (id TEXT PRIMARY KEY REFERENCES institutions(id), corporation_id TEXT, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE corporations (id TEXT PRIMARY KEY REFERENCES institutions(id), status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE house_affiliations (house_id TEXT NOT NULL REFERENCES houses(id), city_id TEXT REFERENCES cities(id), corporation_id TEXT REFERENCES corporations(id), joined_game_day BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE', PRIMARY KEY (house_id, corporation_id));
CREATE TABLE institution_governance_roles (id BIGSERIAL PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), human_id TEXT NOT NULL REFERENCES humans(id), role_code TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE constitutional_rules (id TEXT PRIMARY KEY, part_number INTEGER NOT NULL, article_number INTEGER NOT NULL DEFAULT 1, rule_number TEXT NOT NULL UNIQUE, title TEXT NOT NULL, description TEXT NOT NULL, default_value TEXT NOT NULL, permitted_values TEXT, authority TEXT NOT NULL DEFAULT 'EARTH', active BOOLEAN NOT NULL DEFAULT TRUE, updated_game_day BIGINT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE governance_rules (id TEXT PRIMARY KEY, institution_id TEXT NOT NULL REFERENCES institutions(id), name TEXT NOT NULL, category TEXT NOT NULL, value_json JSONB NOT NULL DEFAULT '{}'::jsonb, quorum_threshold NUMERIC NOT NULL CHECK (quorum_threshold >= 0 AND quorum_threshold <= 1), approval_threshold NUMERIC NOT NULL CHECK (approval_threshold >= 0 AND approval_threshold <= 1), voting_period_days INTEGER NOT NULL CHECK (voting_period_days > 0), implementation_delay_days INTEGER NOT NULL DEFAULT 0 CHECK (implementation_delay_days >= 0), version INTEGER NOT NULL CHECK (version > 0), status TEXT NOT NULL, created_by TEXT, effective_from_game_day BIGINT NOT NULL DEFAULT 1, effective_to_game_day BIGINT, UNIQUE (institution_id, category, version));
CREATE TABLE economic_policy_rules (code TEXT PRIMARY KEY, output_multiplier NUMERIC(8,4) NOT NULL CHECK (output_multiplier >= 0), cost_multiplier NUMERIC(8,4) NOT NULL CHECK (cost_multiplier >= 0), decay_multiplier NUMERIC(8,4) NOT NULL CHECK (decay_multiplier >= 0), is_selectable BOOLEAN NOT NULL DEFAULT TRUE, description TEXT NOT NULL);

CREATE TABLE economic_assets (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, asset_kind TEXT NOT NULL CHECK (asset_kind IN ('CREDIT','RESOURCE')));
CREATE TABLE owner_registry (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL CHECK (owner_type IN ('HOUSE','CITY','CORPORATION','SYSTEM')), economic_id TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE economic_account_types (code TEXT PRIMARY KEY, asset_kind TEXT NOT NULL, is_escrow BOOLEAN NOT NULL DEFAULT FALSE);
CREATE TABLE economic_accounts (id BIGSERIAL PRIMARY KEY, owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), asset_id INTEGER NOT NULL REFERENCES economic_assets(id), account_type TEXT NOT NULL REFERENCES economic_account_types(code), balance_units BIGINT NOT NULL DEFAULT 0 CHECK (balance_units >= 0), status TEXT NOT NULL DEFAULT 'ACTIVE', UNIQUE (owner_economic_id, asset_id, account_type));
CREATE TABLE economic_transactions (id BIGSERIAL PRIMARY KEY, correlation_id TEXT NOT NULL UNIQUE, game_day BIGINT NOT NULL, game_minute INTEGER NOT NULL, transaction_kind TEXT NOT NULL, source_type TEXT NOT NULL, source_id TEXT, rules_version TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE economic_entries (id BIGSERIAL PRIMARY KEY, transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id), account_id BIGINT NOT NULL REFERENCES economic_accounts(id), delta_units BIGINT NOT NULL CHECK (delta_units <> 0), asset_id INTEGER NOT NULL REFERENCES economic_assets(id), UNIQUE (transaction_id, account_id));
CREATE TABLE monetary_supply_snapshots (game_day BIGINT PRIMARY KEY, issued_total_units BIGINT NOT NULL, retired_total_units BIGINT NOT NULL, circulating_units BIGINT NOT NULL, escrow_units BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());

CREATE TABLE building_catalog (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 5), construction_credit_units BIGINT NOT NULL CHECK (construction_credit_units >= 0), construction_minutes INTEGER NOT NULL CHECK (construction_minutes > 0), operating_credit_units BIGINT NOT NULL CHECK (operating_credit_units >= 0), resource_input_units JSONB NOT NULL DEFAULT '{}'::jsonb, resource_output_units JSONB NOT NULL DEFAULT '{}'::jsonb, service_type TEXT, service_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (service_capacity_units >= 0), slot_footprint INTEGER NOT NULL DEFAULT 1 CHECK (slot_footprint > 0), definition_version TEXT NOT NULL);
CREATE TABLE buildings (id TEXT PRIMARY KEY, owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), catalog_id TEXT NOT NULL REFERENCES building_catalog(id), city_id TEXT REFERENCES cities(id), status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','DESTROYED')), started_game_day BIGINT NOT NULL, UNIQUE (id, owner_economic_id));
CREATE TABLE building_catalog_effects (catalog_id TEXT NOT NULL REFERENCES building_catalog(id), effect_code TEXT NOT NULL, effect_value BIGINT NOT NULL CHECK (effect_value >= 0), rules_version TEXT NOT NULL DEFAULT 'building-effects-v1', PRIMARY KEY (catalog_id, effect_code, rules_version));

CREATE TABLE market_instruments (id TEXT PRIMARY KEY, symbol TEXT NOT NULL UNIQUE, asset_id INTEGER NOT NULL REFERENCES economic_assets(id), quote_asset_id INTEGER NOT NULL REFERENCES economic_assets(id), status TEXT NOT NULL DEFAULT 'ACTIVE');
CREATE TABLE market_batches (id BIGSERIAL PRIMARY KEY, game_day BIGINT NOT NULL, game_minute INTEGER NOT NULL, status TEXT NOT NULL CHECK (status IN ('OPEN','CLEARING','COMPLETED','FAILED')), correlation_id TEXT NOT NULL UNIQUE, completed_transaction_id BIGINT REFERENCES economic_transactions(id));
CREATE TABLE market_orders (id TEXT PRIMARY KEY, batch_id BIGINT NOT NULL REFERENCES market_batches(id), instrument_id TEXT NOT NULL REFERENCES market_instruments(id), owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), side TEXT NOT NULL CHECK (side IN ('BUY','SELL')), quantity_units BIGINT NOT NULL CHECK (quantity_units > 0), remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0), limit_price_units BIGINT NOT NULL CHECK (limit_price_units > 0), status TEXT NOT NULL DEFAULT 'OPEN', rules_version TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK (remaining_units <= quantity_units));
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
  scope TEXT NOT NULL CHECK (scope IN ('global', 'city', 'corporation', 'community', 'direct')),
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

CREATE TABLE tax_governance_rules (scope TEXT NOT NULL CHECK (scope IN ('OUC','CITY','CORPORATION')), category TEXT NOT NULL, minimum_rate_bps INTEGER NOT NULL DEFAULT 0 CHECK (minimum_rate_bps >= 0), maximum_rate_bps INTEGER NOT NULL CHECK (maximum_rate_bps >= minimum_rate_bps AND maximum_rate_bps <= 10000), allowed_tax_base_definitions JSONB NOT NULL CHECK (jsonb_typeof(allowed_tax_base_definitions) = 'array'), beneficiary_scope TEXT NOT NULL CHECK (beneficiary_scope IN ('OUC','CITY','CORPORATION')), rules_version TEXT NOT NULL, PRIMARY KEY (scope, category));
CREATE TABLE tax_rule_versions (id TEXT PRIMARY KEY, tax_rule_id TEXT NOT NULL, scope TEXT NOT NULL, category TEXT NOT NULL, version INTEGER NOT NULL, effective_from_game_day BIGINT NOT NULL, effective_to_game_day BIGINT, rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0), tax_base_definition TEXT NOT NULL, beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), authorization_proposal_id TEXT, UNIQUE (tax_rule_id, version), CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day));
CREATE TABLE tax_obligations (id TEXT PRIMARY KEY, taxpayer_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id), tax_type TEXT NOT NULL, tax_base_units BIGINT NOT NULL CHECK (tax_base_units >= 0), amount_units BIGINT NOT NULL CHECK (amount_units >= 0), rule_version TEXT NOT NULL, game_day BIGINT NOT NULL, status TEXT NOT NULL, payment_transaction_id BIGINT REFERENCES economic_transactions(id));

CREATE TABLE fiscal_periods (id TEXT PRIMARY KEY, period_type TEXT NOT NULL, start_game_day BIGINT NOT NULL, end_game_day BIGINT NOT NULL CHECK (end_game_day >= start_game_day), status TEXT NOT NULL);
CREATE TABLE budget_categories (id TEXT PRIMARY KEY, institution_kind TEXT NOT NULL, category_code TEXT NOT NULL, spending_class TEXT NOT NULL CHECK (spending_class IN ('MANDATORY','DISCRETIONARY')), priority INTEGER NOT NULL, UNIQUE (institution_kind, category_code));
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

CREATE TABLE proposals (id TEXT PRIMARY KEY, institution_id TEXT REFERENCES institutions(id), created_by_human_id TEXT NOT NULL REFERENCES humans(id), action_type TEXT NOT NULL, status TEXT NOT NULL, created_game_day BIGINT NOT NULL);
ALTER TABLE tax_rule_versions ADD CONSTRAINT tax_rule_versions_proposal_fk FOREIGN KEY (authorization_proposal_id) REFERENCES proposals(id);
CREATE TABLE ballots (proposal_id TEXT NOT NULL REFERENCES proposals(id), house_id TEXT NOT NULL REFERENCES houses(id), cast_by_human_id TEXT NOT NULL REFERENCES humans(id), choice TEXT NOT NULL, PRIMARY KEY (proposal_id, house_id));
CREATE TABLE event_outbox (id TEXT PRIMARY KEY, event_key TEXT NOT NULL UNIQUE, topic TEXT NOT NULL, aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0), available_at TIMESTAMPTZ NOT NULL DEFAULT now(), locked_at TIMESTAMPTZ, processed_at TIMESTAMPTZ, last_error TEXT, status TEXT NOT NULL DEFAULT 'PENDING', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE scheduler_runs (id BIGSERIAL PRIMARY KEY, game_day BIGINT NOT NULL, phase TEXT NOT NULL, status TEXT NOT NULL, correlation_id TEXT NOT NULL UNIQUE, started_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ);
CREATE TABLE daily_settlement_control (id TEXT PRIMARY KEY CHECK (id = 'WORLD'), status TEXT NOT NULL CHECK (status IN ('awaiting_baseline','active','paused')) DEFAULT 'awaiting_baseline', activated_at TIMESTAMPTZ, activated_by TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE daily_settlement_runs (game_day BIGINT PRIMARY KEY CHECK (game_day >= 1), status TEXT NOT NULL CHECK (status IN ('pending','running','completed','failed','baseline','paused')), current_phase TEXT, attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0), lease_owner TEXT, lease_heartbeat_at TIMESTAMPTZ, rules_version TEXT NOT NULL DEFAULT 'daily-settlement-v1', started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, error_message TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX economic_entries_transaction_idx ON economic_entries(transaction_id);
CREATE UNIQUE INDEX auth_email_deliveries_correlation_uq ON auth_email_deliveries(correlation_id);
CREATE INDEX auth_email_deliveries_account_idx ON auth_email_deliveries(account_id, created_at);
CREATE INDEX market_orders_open_idx ON market_orders(instrument_id, status, side, limit_price_units, created_at);
CREATE INDEX market_fills_orders_idx ON market_fills(buy_order_id, sell_order_id);
CREATE INDEX tax_obligations_taxpayer_idx ON tax_obligations(taxpayer_economic_id, status);
CREATE INDEX outbox_pending_idx ON event_outbox(status, created_at);
