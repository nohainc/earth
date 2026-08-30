-- EARTH PostgreSQL bootstrap baseline through migration 74.
--
-- This file is self-contained: it contains the canonical schema and schema
-- evolution that a new, empty database needs. Do not add new changes here.
--
-- AI agents: read this file and db/schema-manifest.json for the current schema.
-- Migrations 001-074 have been permanently consolidated here; Git history is
-- their archive. All new schema work starts at migration 075 (or the next
-- higher number).
--
-- Run with: psql "$DATABASE_URL" -f db/initial.sql
-- Then run npm run db:migrate:postgres, followed by db/seed.sql.

-- -----------------------------------------------------------------------------
-- Historical migration 001_initial.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH v0.1 authoritative relational baseline.
-- Money and ownership changes are append-only/auditable; projections are derived.
create table if not exists humans (
  id text primary key,
  account_id text not null unique,
  display_name text not null,
  age_years integer not null default 31,
  standing integer not null default 0,
  legacy integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists succession_plans (
  human_id text primary key references humans(id),
  successor_name text not null,
  registered_game_day bigint not null,
  estate_period_days integer not null default 30
);

create table if not exists institutions (
  id text primary key,
  kind text not null check (kind in ('OUC','CORPORATION','CITY','BUSINESS')),
  name text not null,
  status text not null default 'active'
);

create table if not exists ledger_entries (
  id uuid primary key,
  game_day bigint not null,
  debit_account text not null,
  credit_account text not null,
  amount numeric(20,2) not null check (amount > 0),
  currency text not null default 'CREDIT',
  reason_type text not null,
  reason_id text,
  rule_version text not null default 'v0.1',
  correlation_id uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists assets (
  id text primary key,
  asset_type text not null,
  current_owner_id text not null,
  condition numeric(5,2),
  metadata jsonb not null default '{}'
);

create table if not exists asset_ownership_events (
  id uuid primary key,
  asset_id text not null references assets(id),
  from_owner_id text,
  to_owner_id text not null,
  reason_type text not null,
  reason_id text,
  game_day bigint not null,
  created_at timestamptz not null default now()
);

create table if not exists market_orders (
  id uuid primary key,
  human_id text not null references humans(id),
  product text not null check (product in ('material','components','energy','compute')),
  quantity integer not null check (quantity > 0),
  limit_price numeric(20,2) not null check (limit_price > 0),
  filled_quantity integer not null default 0 check (filled_quantity >= 0),
  status text not null default 'open' check (status in ('open','partial','filled','rejected','cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists market_trades (
  id uuid primary key,
  order_id uuid not null references market_orders(id),
  product text not null,
  quantity integer not null check (quantity > 0),
  clearing_price numeric(20,2) not null check (clearing_price > 0),
  game_day bigint not null,
  created_at timestamptz not null default now()
);

create table if not exists proposals (
  id text primary key,
  institution_id text not null references institutions(id),
  title text not null,
  body text not null,
  status text not null default 'open',
  opens_at timestamptz not null,
  closes_at timestamptz not null
);

create table if not exists ballots (
  proposal_id text not null references proposals(id),
  human_id text not null references humans(id),
  choice text not null check (choice in ('support','oppose','abstain')),
  weight numeric(10,3) not null default 1,
  created_at timestamptz not null default now(),
  primary key (proposal_id, human_id)
);

create table if not exists technologies (
  id text primary key,
  name text not null,
  owner_id text,
  progress numeric(5,2) not null default 0,
  version integer not null default 1,
  metadata jsonb not null default '{}'
);

create table if not exists world_state (
  id text primary key,
  game_day bigint not null,
  game_minute integer not null default 0,
  health integer not null default 68,
  market_batch_seconds integer not null default 498
);

create table if not exists businesses (
  id text primary key,
  owner_id text not null references humans(id),
  name text not null,
  policy text not null default 'reliability',
  condition numeric(5,2) not null default 100
);

create table if not exists resource_balances (
  owner_id text not null,
  resource text not null check (resource in ('material','components','energy','compute')),
  amount numeric(20,2) not null default 0,
  primary key (owner_id, resource)
);

create index if not exists ledger_game_day_idx on ledger_entries(game_day);
create index if not exists market_orders_book_idx on market_orders(product, status, limit_price, created_at);
create index if not exists ownership_history_idx on asset_ownership_events(asset_id, game_day);

-- -----------------------------------------------------------------------------
-- Historical migration 002_earth_feature_schema.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL feature schema.
-- This is the reviewed PostgreSQL equivalent of D1 migrations 0003–0050.
-- Apply only after 001_initial.sql and only through a reviewed migration runner.
-- It is intentionally additive and does not drop or rewrite existing data.

create table if not exists communities (
  id text primary key,
  name text not null,
  founder_id text not null references humans(id),
  status text not null default 'active',
  shared_credits numeric(20,2) not null default 0 check (shared_credits >= 0)
);
create table if not exists community_members (
  community_id text not null references communities(id),
  human_id text not null references humans(id),
  role text not null default 'member' check (role in ('founder','member')),
  joined_game_day bigint not null,
  primary key (community_id, human_id)
);
create index if not exists community_members_human_idx on community_members(human_id);

create table if not exists cities (
  id text primary key,
  institution_id text not null unique references institutions(id),
  residents integer not null default 0,
  housing_capacity integer not null default 0,
  energy_capacity integer not null default 0,
  connectivity_capacity integer not null default 0,
  health_capacity integer not null default 0,
  treasury numeric(20,2) not null default 0 check (treasury >= 0)
);
create table if not exists corporations (
  id text primary key,
  institution_id text not null unique references institutions(id),
  member_count integer not null default 0,
  treasury numeric(20,2) not null default 0 check (treasury >= 0),
  constitution_version integer not null default 1
);
create table if not exists memberships (
  human_id text primary key references humans(id),
  corporation_id text references corporations(id),
  city_id text references cities(id),
  joined_game_day bigint not null
);
create table if not exists budgets (
  id text primary key,
  institution_id text not null references institutions(id),
  category text not null,
  amount numeric(20,2) not null default 0 check (amount >= 0),
  game_day bigint not null
);
create table if not exists machines (
  id text primary key,
  owner_id text not null references humans(id),
  name text not null,
  machine_type text not null,
  condition numeric(10,4) not null default 100 check (condition between 0 and 100),
  utilization numeric(10,4) not null default 0,
  maintenance_due bigint not null default 0,
  productive_capacity numeric(20,6) not null default 1
);
create table if not exists maintenance_events (
  id text primary key,
  machine_id text not null references machines(id),
  owner_id text not null references humans(id),
  resource text not null,
  amount numeric(20,6) not null check (amount > 0),
  condition_before numeric(10,4) not null,
  condition_after numeric(10,4) not null,
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create table if not exists research_projects (
  id text primary key,
  technology_id text not null references technologies(id),
  owner_id text not null references humans(id),
  budget numeric(20,2) not null default 0,
  progress numeric(10,4) not null default 0,
  status text not null default 'active',
  started_game_day bigint not null
);
create table if not exists patents (
  id text primary key,
  technology_id text not null references technologies(id),
  owner_id text not null references humans(id),
  granted_game_day bigint not null,
  expiry_game_day bigint not null,
  status text not null default 'active'
);
create table if not exists technology_licenses (
  id text primary key,
  patent_id text not null references patents(id),
  licensor_id text not null references humans(id),
  licensee_id text not null references humans(id),
  royalty_rate numeric(10,6) not null default 0,
  status text not null default 'active'
);
create table if not exists account_balances (
  account_id text primary key,
  owner_id text not null,
  balance numeric(20,2) not null default 0 check (balance >= 0),
  currency text not null default 'CREDIT'
);
create table if not exists market_prices (
  product text primary key,
  price numeric(20,6) not null check (price > 0),
  supply numeric(20,6) not null default 0,
  demand numeric(20,6) not null default 0,
  game_day bigint not null
);

create table if not exists auth_credentials (
  human_id text primary key references humans(id),
  email text not null unique,
  password_hash text not null,
  password_salt text not null,
  password_iterations integer not null default 100000,
  email_verified_at timestamptz,
  mfa_secret text,
  mfa_enabled boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists auth_sessions (
  id text primary key,
  human_id text not null references humans(id),
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index if not exists auth_sessions_token_idx on auth_sessions(token_hash, expires_at);
create table if not exists auth_login_attempts (
  email text primary key,
  window_started_at timestamptz not null,
  attempt_count integer not null default 0,
  blocked_until timestamptz
);
create index if not exists auth_login_block_idx on auth_login_attempts(blocked_until);
create table if not exists auth_action_tokens (
  id text primary key,
  human_id text not null references humans(id),
  token_hash text not null unique,
  action text not null check (action in ('verify_email','reset_password')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists auth_action_tokens_lookup_idx on auth_action_tokens(token_hash, action, expires_at);

alter table humans add column if not exists life_status text not null default 'active' check (life_status in ('active','deceased','estate'));
alter table humans add column if not exists death_game_day bigint;
alter table humans add column if not exists political_eligibility_game_day bigint not null default 0;
alter table succession_plans add column if not exists successor_human_id text references humans(id);
create table if not exists life_events (
  id text primary key,
  human_id text not null references humans(id),
  event_type text not null check (event_type in ('birth','death','inheritance')),
  game_day bigint not null,
  successor_name text,
  estate_credits numeric(20,2) not null default 0 check (estate_credits >= 0),
  created_at timestamptz not null default now()
);
create index if not exists life_events_human_idx on life_events(human_id, game_day desc);

alter table world_state add column if not exists living_cost_index numeric(10,4) not null default 1.0;
alter table world_state add column if not exists essential_services_index numeric(10,4) not null default 0.68;
alter table businesses add column if not exists status text not null default 'active' check (status in ('active','distressed','bankrupt'));
alter table businesses add column if not exists sector text not null default 'maintenance';
alter table machines add column if not exists output_resource text not null default 'components';
alter table machines add column if not exists input_resource text not null default 'energy';
alter table machines add column if not exists input_per_output numeric(20,6) not null default 0.25;
create index if not exists machines_output_resource_idx on machines(output_resource, condition, utilization);
create index if not exists machines_input_resource_idx on machines(input_resource, condition, utilization);

create table if not exists production_events (
  id text primary key,
  machine_id text not null references machines(id),
  owner_id text not null references humans(id),
  resource text not null check (resource in ('material','components','energy','compute')),
  amount numeric(20,6) not null check (amount > 0),
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists production_events_owner_idx on production_events(owner_id, game_day desc);
create table if not exists machine_acquisitions (
  id text primary key,
  machine_id text not null references machines(id),
  owner_id text not null references humans(id),
  machine_type text not null,
  credit_cost numeric(20,2) not null check (credit_cost >= 0),
  material_cost numeric(20,6) not null check (material_cost >= 0),
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists machine_acquisitions_owner_idx on machine_acquisitions(owner_id, game_day desc);
create table if not exists recycling_events (
  id text primary key,
  machine_id text not null references machines(id),
  owner_id text not null references humans(id),
  material_returned numeric(20,6) not null default 0 check (material_returned >= 0),
  components_returned numeric(20,6) not null default 0 check (components_returned >= 0),
  efficiency numeric(10,6) not null,
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists recycling_events_owner_idx on recycling_events(owner_id, game_day desc);
create table if not exists machine_upgrade_events (
  id text primary key,
  machine_id text not null references machines(id),
  owner_id text not null references humans(id),
  credit_cost numeric(20,2) not null check (credit_cost >= 0),
  components_cost numeric(20,6) not null check (components_cost >= 0),
  capacity_before numeric(20,6) not null,
  capacity_after numeric(20,6) not null,
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists machine_upgrade_events_owner_idx on machine_upgrade_events(owner_id, game_day desc);
create table if not exists machine_sales (
  id text primary key,
  machine_id text not null references machines(id),
  seller_id text not null references humans(id),
  buyer_id text not null references humans(id),
  price numeric(20,2) not null check (price > 0),
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists machine_sales_participant_idx on machine_sales(seller_id, buyer_id, game_day desc);

alter table maintenance_events add column if not exists correlation_id text;
create unique index if not exists maintenance_events_machine_correlation_idx on maintenance_events(machine_id, correlation_id) where correlation_id is not null;
create table if not exists ownership_events (
  id text primary key,
  asset_type text not null,
  asset_id text not null,
  from_owner_id text,
  to_owner_id text not null,
  quantity numeric(20,6) not null default 1 check (quantity > 0),
  reason_type text not null,
  reason_id text,
  game_day bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists ownership_events_asset_idx on ownership_events(asset_type, asset_id, game_day desc);
create index if not exists ownership_events_owner_idx on ownership_events(to_owner_id, game_day desc);

alter table market_orders add column if not exists side text not null default 'buy' check (side in ('buy','sell'));
alter table market_orders add column if not exists correlation_id text;
alter table market_orders add column if not exists reserved_credits numeric(20,2) not null default 0 check (reserved_credits >= 0);
create index if not exists market_orders_matching_idx on market_orders(product, side, status, limit_price, created_at);
create index if not exists market_orders_reserved_idx on market_orders(human_id, side, status, reserved_credits);
create unique index if not exists market_orders_human_correlation_idx on market_orders(human_id, correlation_id) where correlation_id is not null;

alter table proposals add column if not exists rule_version_id text;
alter table proposals add column if not exists quorum numeric(10,6) not null default 0.25;
alter table proposals add column if not exists approval_threshold numeric(10,6) not null default 0.5;
alter table proposals add column if not exists implementation_delay_days integer not null default 1;
alter table proposals add column if not exists outcome text not null default 'pending' check (outcome in ('pending','passed','rejected','no_quorum'));
alter table proposals add column if not exists implementation_at timestamptz;
alter table proposals add column if not exists resolved_at timestamptz;
alter table proposals add column if not exists target_category text;
alter table proposals add column if not exists target_value_json jsonb;
alter table proposals add column if not exists executed_at timestamptz;
alter table proposals add column if not exists execution_status text not null default 'not_ready' check (execution_status in ('not_ready','ready','executed','skipped'));
alter table proposals add column if not exists correlation_id text;
create unique index if not exists proposals_institution_correlation_idx on proposals(institution_id, correlation_id) where correlation_id is not null;
create table if not exists governance_rules (
  id text primary key,
  institution_id text not null references institutions(id),
  name text not null,
  category text not null,
  value_json jsonb not null default '{}',
  version integer not null,
  status text not null default 'active' check (status in ('draft','active','superseded','repealed')),
  created_by text not null references humans(id),
  created_at timestamptz not null default now(),
  unique (institution_id, category, version)
);
create table if not exists institution_roles (
  id text primary key,
  institution_id text not null references institutions(id),
  name text not null,
  authority_json jsonb not null default '{}',
  term_days integer not null default 30,
  eligibility text not null default 'member',
  status text not null default 'active' check (status in ('active','retired')),
  unique (institution_id, name)
);
create table if not exists role_assignments (
  id text primary key,
  role_id text not null references institution_roles(id),
  institution_id text not null references institutions(id),
  human_id text not null references humans(id),
  started_game_day bigint not null,
  ends_game_day bigint not null,
  status text not null default 'active' check (status in ('active','expired','resigned')),
  created_at timestamptz not null default now()
);
create unique index if not exists active_role_assignment_idx on role_assignments(role_id) where status = 'active';
create table if not exists authority_delegations (
  id text primary key,
  institution_id text not null references institutions(id),
  role_id text not null references institution_roles(id),
  delegator_id text not null references humans(id),
  delegate_id text not null references humans(id),
  starts_game_day bigint not null,
  ends_game_day bigint not null,
  status text not null default 'active' check (status in ('active','revoked','expired')),
  created_at timestamptz not null default now(),
  check (delegator_id <> delegate_id)
);
create unique index if not exists active_role_delegation_idx on authority_delegations(role_id) where status = 'active';
create index if not exists authority_delegation_delegate_idx on authority_delegations(delegate_id, institution_id, status);

create table if not exists membership_events (
  id text primary key,
  human_id text not null references humans(id),
  institution_type text not null,
  institution_id text not null,
  action text not null check (action in ('joined','left','released')),
  game_day bigint not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create index if not exists membership_events_human_idx on membership_events(human_id, game_day desc);
create index if not exists membership_events_institution_idx on membership_events(institution_id, game_day desc);
create table if not exists authority_events (
  id text primary key,
  human_id text not null references humans(id),
  institution_id text not null,
  role_id text not null,
  action text not null check (action in ('claimed','resigned','expired','released')),
  game_day bigint not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists authority_events_transition_idx on authority_events(human_id, role_id, action, game_day);
create index if not exists authority_events_human_idx on authority_events(human_id, game_day desc);
create index if not exists authority_events_institution_idx on authority_events(institution_id, game_day desc);

create table if not exists notifications (
  id text primary key,
  human_id text not null references humans(id),
  notification_type text not null,
  title text not null,
  body text not null,
  entity_id text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_human_idx on notifications(human_id, read_at, created_at desc);
create table if not exists world_events (
  id text primary key,
  game_day bigint not null,
  event_type text not null,
  title text not null,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists world_events_day_idx on world_events(game_day desc);
create table if not exists rankings_snapshots (
  id text primary key,
  game_day bigint not null,
  ranking_type text not null,
  entity_id text not null,
  rank integer not null,
  score numeric(20,6) not null,
  created_at timestamptz not null default now(),
  unique (game_day, ranking_type, entity_id)
);
create index if not exists rankings_snapshots_type_idx on rankings_snapshots(ranking_type, game_day desc, rank);
create table if not exists deceased_profiles (
  human_id text primary key references humans(id),
  display_name text not null,
  death_game_day bigint not null,
  final_standing integer not null,
  final_legacy integer not null,
  successor_name text,
  archived_at timestamptz not null default now()
);

create table if not exists financial_states (
  institution_id text primary key,
  institution_kind text not null check (institution_kind in ('BUSINESS','CITY','CORPORATION')),
  status text not null check (status in ('active','distressed','insolvent','bankrupt')),
  since_game_day bigint not null,
  recovery_game_day bigint,
  last_reason text not null default '',
  updated_at timestamptz not null default now()
);
create index if not exists financial_states_status_idx on financial_states(status, institution_kind);
create table if not exists bankruptcy_events (
  id text primary key,
  institution_id text not null,
  institution_kind text not null,
  from_status text not null,
  to_status text not null,
  game_day bigint not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create table if not exists personal_financial_states (
  human_id text primary key references humans(id),
  status text not null check (status in ('active','distressed','insolvent','bankrupt')),
  since_game_day bigint not null,
  protected_credits numeric(20,2) not null default 100,
  last_reason text not null default '',
  updated_at timestamptz not null default now()
);
create index if not exists personal_financial_status_idx on personal_financial_states(status, since_game_day);

create table if not exists business_shares (
  business_id text not null references businesses(id),
  holder_id text not null references humans(id),
  shares bigint not null check (shares > 0),
  updated_at timestamptz not null default now(),
  primary key (business_id, holder_id)
);
create index if not exists business_shares_holder_idx on business_shares(holder_id);
create table if not exists business_constitutions (
  business_id text primary key references businesses(id),
  version integer not null default 1,
  shareholder_vote_threshold numeric(10,6) not null default 0.5 check (shareholder_vote_threshold > 0 and shareholder_vote_threshold <= 1),
  board_approval_threshold numeric(10,6) not null default 0.5 check (board_approval_threshold > 0 and board_approval_threshold <= 1),
  dilution_notice_days integer not null default 3 check (dilution_notice_days between 0 and 30),
  updated_by text not null references humans(id),
  updated_game_day bigint not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists business_constitutions_version_idx on business_constitutions(version, updated_game_day);
create table if not exists business_management (
  business_id text primary key references businesses(id),
  manager_id text not null references humans(id),
  appointed_by text not null references humans(id),
  appointed_game_day bigint not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists business_financials (
  business_id text primary key references businesses(id),
  revenue numeric(20,2) not null default 0 check (revenue >= 0),
  operating_costs numeric(20,2) not null default 0 check (operating_costs >= 0),
  profit numeric(20,2) not null default 0,
  last_game_day bigint not null default 0,
  taxed_revenue numeric(20,2) not null default 0 check (taxed_revenue >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists business_assets (
  business_id text not null references businesses(id),
  machine_id text primary key references machines(id),
  assigned_game_day bigint not null,
  assigned_by text not null
);

create table if not exists negotiated_contracts (
  id text primary key,
  kind text not null check (kind in ('employment','intellectual_service','capacity','strategic')),
  proposer_id text not null references humans(id),
  counterparty_id text not null references humans(id),
  title text not null,
  terms_json jsonb not null default '{}',
  amount numeric(20,2) not null default 0 check (amount >= 0),
  status text not null default 'proposed' check (status in ('proposed','accepted','cancelled','completed')),
  starts_game_day bigint not null,
  ends_game_day bigint not null,
  accepted_game_day bigint,
  correlation_id text,
  created_at timestamptz not null default now(),
  check (proposer_id <> counterparty_id)
);
create index if not exists negotiated_contracts_party_idx on negotiated_contracts(proposer_id, counterparty_id, status);
create unique index if not exists negotiated_contracts_correlation_idx on negotiated_contracts(proposer_id, correlation_id) where correlation_id is not null;
create table if not exists contract_disputes (
  id text primary key,
  contract_id text not null references negotiated_contracts(id),
  claimant_id text not null references humans(id),
  respondent_id text not null references humans(id),
  reason text not null,
  status text not null default 'open' check (status in ('open','resolved','rejected')),
  outcome text check (outcome in ('uphold','void')),
  resolved_by text references humans(id),
  resolved_game_day bigint,
  resolution text,
  created_at timestamptz not null default now()
);
create unique index if not exists open_contract_dispute_idx on contract_disputes(contract_id) where status = 'open';

create table if not exists ai_assistants (
  id text primary key,
  owner_id text not null references humans(id),
  tier text not null check (tier in ('basic','business')),
  policy text not null default 'recommend',
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists ai_assistants_owner_idx on ai_assistants(owner_id, enabled);
create table if not exists tax_rules (
  id text primary key,
  scope text not null,
  category text not null,
  rate numeric(10,6) not null check (rate >= 0 and rate <= 1),
  active boolean not null default true,
  version integer not null default 1
);

create table if not exists earth_schema_migrations (
  version integer primary key,
  name text not null,
  applied_at timestamptz not null default now(),
  checksum text not null
);

-- -----------------------------------------------------------------------------
-- Historical migration 003_import_compatibility.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Compatibility structures discovered during the non-destructive D1 export review.
-- Kept separate so migration 002 remains checksum-stable after application.
create table if not exists resource_balances (
  owner_id text not null,
  resource text not null check (resource in ('material','components','energy','compute')),
  amount numeric(20,6) not null default 0 check (amount >= 0),
  primary key (owner_id, resource)
);
alter table research_projects add column if not exists focus text not null default 'efficiency' check (focus in ('efficiency','durability','safety','cost'));

-- -----------------------------------------------------------------------------
-- Historical migration 004_correlation_key_compatibility.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- D1 correlation IDs are opaque idempotency keys, not UUIDs.
alter table ledger_entries alter column correlation_id type text using correlation_id::text;

-- -----------------------------------------------------------------------------
-- Historical migration 005_institution_dissolution.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Prolonged insolvency ends in an auditable dissolution, matching the game lifecycle.
alter table financial_states drop constraint if exists financial_states_status_check;
alter table financial_states add constraint financial_states_status_check check (status in ('active','distressed','insolvent','bankrupt','dissolved'));

-- -----------------------------------------------------------------------------
-- Historical migration 006_event_outbox.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Transactional side-effect queue. Domain mutations write here in the same
-- PostgreSQL transaction as their ledger/event changes; delivery is retried
-- by the scheduled Worker until the event is acknowledged.
create table if not exists event_outbox (
  id uuid primary key,
  event_key text not null unique,
  topic text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  payload jsonb not null default '{}',
  available_at timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  locked_at timestamptz,
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);
create index if not exists event_outbox_pending_idx
  on event_outbox(available_at, created_at)
  where processed_at is null;
create index if not exists event_outbox_aggregate_idx
  on event_outbox(aggregate_type, aggregate_id, created_at);

-- -----------------------------------------------------------------------------
-- Historical migration 007_game_time_governance_windows.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Governance windows are authoritative in game time. Existing real-time
-- timestamps remain as historical compatibility fields and audit metadata.
alter table proposals add column if not exists closes_game_day bigint;
alter table proposals add column if not exists closes_game_minute integer;
alter table proposals add column if not exists implementation_game_day bigint;
alter table proposals add column if not exists implementation_game_minute integer;

with clock as (
  select game_day, game_minute
  from world_state
  where id = 'WORLD'
), projected as (
  select
    p.id,
    (clock.game_day * 1440 + clock.game_minute + greatest(0, floor(extract(epoch from (p.closes_at - current_timestamp)) / 60)))::bigint as close_absolute_minute,
    case
      when p.implementation_at is null then null
      else (clock.game_day * 1440 + clock.game_minute + greatest(0, floor(extract(epoch from (p.implementation_at - current_timestamp)) / 60)))::bigint
    end as implementation_absolute_minute
  from proposals p
  cross join clock
  where p.closes_game_day is null
)
update proposals p
set closes_game_day = floor(projected.close_absolute_minute / 1440.0)::bigint,
    closes_game_minute = mod(projected.close_absolute_minute, 1440)::integer,
    implementation_game_day = case when projected.implementation_absolute_minute is null then null else floor(projected.implementation_absolute_minute / 1440.0)::bigint end,
    implementation_game_minute = case when projected.implementation_absolute_minute is null then null else mod(projected.implementation_absolute_minute, 1440)::integer end
from projected
where p.id = projected.id;

alter table proposals drop constraint if exists proposals_closes_game_minute_check;
alter table proposals add constraint proposals_closes_game_minute_check check (closes_game_minute between 0 and 1439);
alter table proposals drop constraint if exists proposals_implementation_game_minute_check;
alter table proposals add constraint proposals_implementation_game_minute_check check (implementation_game_minute between 0 and 1439);
create index if not exists proposals_game_deadline_idx on proposals(status, closes_game_day, closes_game_minute);

-- -----------------------------------------------------------------------------
-- Historical migration 008_atomic_credit_transfer.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Narrow financial primitive: keep balance mutation and its audit entry atomic.
-- Gameplay policy (who may pay, how much tax applies, and which rule version is
-- selected) remains in TypeScript. This function only protects the contested
-- database mutation once the policy has already been decided.
create or replace function earth_transfer_credits(
  p_ledger_id uuid,
  p_game_day bigint,
  p_debit_account text,
  p_credit_account text,
  p_amount numeric(20,2),
  p_reason_type text,
  p_reason_id text,
  p_rule_version text,
  p_correlation_id text
)
returns table (
  status text,
  ledger_id uuid,
  amount numeric(20,2),
  already_processed boolean
)
language plpgsql
as $$
declare
  account_count integer;
begin
  if p_debit_account is null or p_credit_account is null or p_debit_account = p_credit_account then
    raise exception 'Credit transfer requires two different accounts';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Credit transfer amount must be positive';
  end if;

  if p_reason_type is null or length(trim(p_reason_type)) = 0 then
    raise exception 'Credit transfer reason type is required';
  end if;

  if p_correlation_id is null or length(trim(p_correlation_id)) = 0 then
    raise exception 'Credit transfer correlation ID is required';
  end if;

  -- Serialize calls using the same business idempotency key. This protects
  -- callers before a future migration adds a global unique index, and does not
  -- hold a lock beyond the surrounding transaction.
  perform pg_advisory_xact_lock(hashtextextended(p_reason_type || ':' || p_correlation_id, 0));

  if exists (
    select 1
    from ledger_entries
    where reason_type = p_reason_type
      and correlation_id::text = p_correlation_id
  ) then
    return query
      select 'already_processed'::text, le.id, le.amount, true
      from ledger_entries le
      where le.reason_type = p_reason_type
        and le.correlation_id::text = p_correlation_id
      order by le.created_at asc, le.id asc
      limit 1;
    return;
  end if;

  select count(*)::integer
    into account_count
  from account_balances
  where account_id in (p_debit_account, p_credit_account)
    and currency = 'CREDIT';

  if account_count <> 2 then
    raise exception 'Credit transfer account not found';
  end if;

  -- Lock in a deterministic order to reduce deadlock risk when two transfers
  -- touch the same pair of accounts in opposite directions.
  perform account_id
  from account_balances
  where account_id in (p_debit_account, p_credit_account)
    and currency = 'CREDIT'
  order by account_id
  for update;

  update account_balances
  set balance = balance - p_amount
  where account_id = p_debit_account
    and currency = 'CREDIT'
    and balance >= p_amount;

  if not found then
    raise exception 'Insufficient Credits';
  end if;

  update account_balances
  set balance = balance + p_amount
  where account_id = p_credit_account
    and currency = 'CREDIT';

  insert into ledger_entries (
    id, game_day, debit_account, credit_account, amount, currency,
    reason_type, reason_id, rule_version, correlation_id
  ) values (
    p_ledger_id, p_game_day, p_debit_account, p_credit_account, p_amount,
    'CREDIT', p_reason_type, p_reason_id, p_rule_version, p_correlation_id
  );

  return query select 'applied'::text, p_ledger_id, p_amount, false;
end;
$$;

-- -----------------------------------------------------------------------------
-- Historical migration 009_market_order_escrow.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Give every open buy order an explicit CREDIT escrow account.
-- New orders fund this account through earth_transfer_credits; this backfill
-- preserves reservations made before escrow became explicit.
insert into account_balances (account_id, owner_id, balance, currency)
select
  'market-order-' || id,
  'market-order-' || id,
  coalesce(reserved_credits, 0),
  'CREDIT'
from market_orders
where side = 'buy'
  and status in ('open', 'partial')
  and coalesce(reserved_credits, 0) > 0
on conflict (account_id) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 010_market_order_escrow_zero_reservations.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Preserve an explicit escrow row even for legacy zero-reservation orders.
-- The application excludes these invalid orders from settlement and allows
-- their owner to cancel them without creating a zero-value ledger entry.
insert into account_balances (account_id, owner_id, balance, currency)
select
  'market-order-' || id,
  'market-order-' || id,
  0,
  'CREDIT'
from market_orders
where side = 'buy'
  and status in ('open', 'partial')
on conflict (account_id) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 011_institution_credit_accounts.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Represent institution-held credits as first-class PostgreSQL credit accounts.
-- The scalar treasury columns remain synchronized read projections for the
-- current API, while all future money movement uses these accounts.
insert into account_balances (account_id, owner_id, balance, currency)
select 'account-community-' || id, id, shared_credits, 'CREDIT'
from communities
on conflict (account_id) do nothing;

insert into account_balances (account_id, owner_id, balance, currency)
select 'account-city-' || id, id, treasury, 'CREDIT'
from cities
on conflict (account_id) do nothing;

insert into account_balances (account_id, owner_id, balance, currency)
select 'account-corporation-' || id, id, treasury, 'CREDIT'
from corporations
on conflict (account_id) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 012_registry_credit_accounts.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Explicit system accounts for credits committed to research and machine
-- registries. These balances preserve the money trail for asset funding.
insert into account_balances (account_id, owner_id, balance, currency)
values
  ('account-research-registry', 'SYSTEM-RESEARCH', 0, 'CREDIT'),
  ('account-machine-registry', 'SYSTEM-MACHINES', 0, 'CREDIT')
on conflict (account_id) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 013_city_budget_accounts.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Earmarked city budgets hold credits separately from the city's available
-- treasury. Existing BUDGET-* rows are backfilled before the new command path.
insert into account_balances (account_id, owner_id, balance, currency)
select 'account-budget-' || id, id, amount, 'CREDIT'
from budgets
where id like 'BUDGET-%'
on conflict (account_id) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 014_recycling_idempotency.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Make destructive machine recycling safely replayable.
alter table recycling_events add column if not exists correlation_id text;
create unique index if not exists recycling_events_machine_correlation_idx
  on recycling_events(machine_id, correlation_id)
  where correlation_id is not null;

-- -----------------------------------------------------------------------------
-- Historical migration 015_business_liquidation_idempotency.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
alter table bankruptcy_events add column if not exists correlation_id text;
create unique index if not exists bankruptcy_events_institution_correlation_idx
  on bankruptcy_events(institution_id, correlation_id)
  where correlation_id is not null;

-- -----------------------------------------------------------------------------
-- Historical migration 016_scheduler_readiness_heartbeat.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
alter table world_state
  add column if not exists last_scheduler_at timestamptz;

-- -----------------------------------------------------------------------------
-- Historical migration 017_initialize_scheduler_heartbeat.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
update world_state
set last_scheduler_at = coalesce(last_scheduler_at, current_timestamp)
where id = 'WORLD';

-- -----------------------------------------------------------------------------
-- Historical migration 018_normalize_json_structures.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- 1. institution_roles: add typed permission boolean columns
alter table institution_roles
  add column if not exists can_propose boolean not null default false,
  add column if not exists can_vote boolean not null default false,
  add column if not exists can_manage_budget boolean not null default false,
  add column if not exists can_manage_treasury boolean not null default false,
  add column if not exists can_appoint_manager boolean not null default false;

-- Backfill boolean columns from authority_json if populated
update institution_roles
set
  can_propose = coalesce((authority_json->>'propose')::boolean, false),
  can_vote = coalesce((authority_json->>'vote')::boolean, false),
  can_manage_budget = coalesce((authority_json->>'budget')::boolean, false),
  can_manage_treasury = coalesce((authority_json->>'treasury')::boolean, false),
  can_appoint_manager = coalesce((authority_json->>'appoint')::boolean, false)
where authority_json is not null and authority_json <> '{}'::jsonb;

-- 2. governance_rules: add typed threshold columns
alter table governance_rules
  add column if not exists quorum_threshold numeric(10,6),
  add column if not exists approval_threshold numeric(10,6),
  add column if not exists voting_period_days integer;

-- Backfill threshold columns from value_json if populated
update governance_rules
set
  quorum_threshold = coalesce((value_json->>'quorum')::numeric, 0.25),
  approval_threshold = coalesce((value_json->>'approval_threshold')::numeric, 0.50),
  voting_period_days = coalesce((value_json->>'term_days')::integer, 30)
where value_json is not null and value_json <> '{}'::jsonb;

-- 3. technologies: add compute and credit costs, and prerequisite junction table
alter table technologies
  add column if not exists required_compute integer not null default 0,
  add column if not exists cost_credits numeric(20,2) not null default 0;

create table if not exists technology_prerequisites (
  technology_id text not null references technologies(id) on delete cascade,
  required_technology_id text not null references technologies(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (technology_id, required_technology_id)
);
create index if not exists technology_prerequisites_req_idx on technology_prerequisites(required_technology_id);

-- 4. merger_contracts: specialized sub-table for strategic business tender offers
create table if not exists merger_contracts (
  contract_id text primary key references negotiated_contracts(id) on delete cascade,
  acquirer_business_id text not null references businesses(id),
  target_business_id text not null references businesses(id),
  price_per_share numeric(20,2) not null check (price_per_share > 0),
  total_shares bigint not null check (total_shares > 0),
  total_amount numeric(20,2) not null check (total_amount > 0),
  created_at timestamptz not null default now()
);
create index if not exists merger_contracts_acquirer_idx on merger_contracts(acquirer_business_id);
create index if not exists merger_contracts_target_idx on merger_contracts(target_business_id);

-- -----------------------------------------------------------------------------
-- Historical migration 019_drop_obsolete_json_columns.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 019: Drop obsolete JSONB columns in favor of typed columns and relational sub-tables

-- 1. institution_roles: drop authority_json (replaced by can_propose, can_vote, can_manage_budget, can_manage_treasury, can_appoint_manager)
alter table institution_roles
  drop column if exists authority_json;

-- 2. governance_rules: drop value_json (replaced by quorum_threshold, approval_threshold, voting_period_days)
alter table governance_rules
  drop column if exists value_json;

-- 3. technologies: drop metadata (replaced by required_compute, cost_credits, technology_prerequisites)
alter table technologies
  drop column if exists metadata;

-- 4. negotiated_contracts: drop terms_json (replaced by merger_contracts sub-table)
alter table negotiated_contracts
  drop column if exists terms_json;

-- 5. assets: drop metadata (replaced by typed machines table)
alter table assets
  drop column if exists metadata;

-- -----------------------------------------------------------------------------
-- Historical migration 020_migrate_to_nano_markup_text.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 020: Migrate event_outbox.payload and proposals.target_value_json to Nano Markup TEXT

alter table event_outbox
  alter column payload type text using payload::text;

alter table proposals
  alter column target_value_json type text using target_value_json::text;

-- -----------------------------------------------------------------------------
-- Historical migration 021_migrate_world_events_to_nano_markup.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 021: Migrate world_events.details to Nano Markup TEXT and add correlation_id

alter table world_events
  add column if not exists correlation_id text;

-- Backfill correlation_id from details if stored as JSON
update world_events
set correlation_id = details->>'correlationId'
where correlation_id is null and details::text like '%correlationId%';

alter table world_events
  alter column details type text using details::text;

create index if not exists world_events_correlation_idx
  on world_events(event_type, correlation_id)
  where correlation_id is not null;

-- -----------------------------------------------------------------------------
-- Historical migration 022_effective_genesis_and_simulation_offset.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 022: Add genesis_at and simulated_day_offset to world_state

alter table world_state
  add column if not exists genesis_at timestamptz not null default '2026-01-01T00:00:00Z',
  add column if not exists simulated_day_offset integer not null default 0;

-- -----------------------------------------------------------------------------
-- Historical migration 023_pantheon_cemetery_and_rebirth.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 023: Enhanced Planetary Cemetery, Pantheon & Character Rebirth Lineage
-- Supports stochastic mortality profile recording, unbroken genealogical trees, and naturalization rebirths.

alter table deceased_profiles add column if not exists birth_game_day bigint not null default 1;
alter table deceased_profiles add column if not exists cause_of_death text not null default 'Natural Aging';
alter table deceased_profiles add column if not exists epitaph text not null default 'Pioneered civilization across the frontier of Earth.';
alter table deceased_profiles add column if not exists lifetime_dividends numeric(20,2) not null default 0;
alter table deceased_profiles add column if not exists predecessor_human_id text;
alter table deceased_profiles add column if not exists dynasty_name text not null default 'Founding Dynasty';

create table if not exists character_lineage (
  id text primary key,
  email text not null,
  human_id text not null references humans(id),
  predecessor_human_id text references humans(id),
  generation integer not null default 1,
  birth_game_day bigint not null default 1,
  death_game_day bigint,
  final_legacy integer not null default 0,
  dynasty_name text not null default 'Founding Dynasty',
  created_at timestamptz not null default now()
);

create index if not exists character_lineage_email_idx on character_lineage(email, generation);
create index if not exists deceased_profiles_rank_idx on deceased_profiles(death_game_day desc, final_legacy desc);
create index if not exists deceased_profiles_dynasty_idx on deceased_profiles(dynasty_name, final_legacy desc);

-- -----------------------------------------------------------------------------
-- Historical migration 024_communications_and_dispatch.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- 024_communications_and_dispatch.sql
-- Migration 024: Universal Comm-Link Frequency Channels & Diplomatic Dispatch System

CREATE TABLE IF NOT EXISTS comm_channels (
    id TEXT PRIMARY KEY,
    scope TEXT NOT NULL CHECK (scope IN ('global', 'city', 'institution', 'direct')),
    scope_id TEXT,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS comm_messages (
    id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL REFERENCES comm_channels(id) ON DELETE CASCADE,
    sender_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    sender_display_name TEXT NOT NULL,
    sender_dynasty_name TEXT,
    body TEXT NOT NULL,
    game_day INT NOT NULL DEFAULT 1,
    game_minute INT NOT NULL DEFAULT 0,
    attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS diplomatic_dispatches (
    id TEXT PRIMARY KEY,
    sender_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    recipient_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'archived')),
    game_day INT NOT NULL DEFAULT 1,
    game_minute INT NOT NULL DEFAULT 0,
    dispatch_type TEXT NOT NULL DEFAULT 'diplomatic' CHECK (dispatch_type IN ('diplomatic', 'contract_offer', 'patent_license', 'merger_tender', 'succession_notice')),
    action_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS comm_messages_channel_idx ON comm_messages (channel_id, game_day DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS diplomatic_dispatches_recipient_idx ON diplomatic_dispatches (recipient_human_id, status, game_day DESC);
CREATE INDEX IF NOT EXISTS diplomatic_dispatches_sender_idx ON diplomatic_dispatches (sender_human_id, created_at DESC);

-- Seed global channels if not present
INSERT INTO comm_channels (id, scope, scope_id, name, description)
VALUES
    ('channel-global-relay', 'global', NULL, 'Planetary Public Relay', 'Universal broadcast frequency for open civilizational discourse and market news.'),
    ('channel-city-new-tokyo', 'city', 'city-new-tokyo', 'Neo-Tokyo City Hall', 'Municipal forum for Neo-Tokyo residents, tax debates, and infrastructure initiatives.'),
    ('channel-city-new-york', 'city', 'city-new-york', 'New York Municipal Council', 'Municipal chamber for New York residents and commercial policy.'),
    ('channel-city-london', 'city', 'city-london', 'London Industrial Forum', 'Municipal chamber for London residents, trade, and industrial supply.'),
    ('channel-city-geneva', 'city', 'city-geneva', 'Geneva Assembly Hall', 'Municipal chamber for Geneva residents and constitutional jurisprudence.'),
    ('channel-city-singapore', 'city', 'city-singapore', 'Singapore Maritime Exchange', 'Municipal forum for Singapore logistics, freight, and trade.')
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 025_allow_food_resource_balance.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 025: Allow food in resource_balances check constraint
alter table resource_balances drop constraint if exists resource_balances_resource_check;
alter table resource_balances add constraint resource_balances_resource_check check (resource in ('food','material','components','energy','compute'));

-- -----------------------------------------------------------------------------
-- Historical migration 026_automated_supply_contracts_and_escrow.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 026: Automated Supply Contracts & Escrow Vaults

CREATE TABLE IF NOT EXISTS supply_contracts (
  contract_id TEXT PRIMARY KEY REFERENCES negotiated_contracts(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL CHECK (resource_type IN ('food', 'energy', 'material', 'compute')),
  daily_quantity NUMERIC(20, 2) NOT NULL CHECK (daily_quantity > 0),
  unit_price NUMERIC(20, 2) NOT NULL CHECK (unit_price > 0),
  total_days INTEGER NOT NULL CHECK (total_days > 0),
  delivered_days INTEGER NOT NULL DEFAULT 0,
  default_days INTEGER NOT NULL DEFAULT 0,
  max_consecutive_defaults INTEGER NOT NULL DEFAULT 3,
  consecutive_defaults INTEGER NOT NULL DEFAULT 0,
  escrow_total NUMERIC(20, 2) NOT NULL CHECK (escrow_total >= 0),
  escrow_remaining NUMERIC(20, 2) NOT NULL CHECK (escrow_remaining >= 0),
  penalty_per_default NUMERIC(20, 2) NOT NULL DEFAULT 0 CHECK (penalty_per_default >= 0),
  last_settled_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contract_escrow_vaults (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES negotiated_contracts(id) ON DELETE CASCADE,
  buyer_id TEXT NOT NULL REFERENCES humans(id),
  seller_id TEXT NOT NULL REFERENCES humans(id),
  locked_amount NUMERIC(20, 2) NOT NULL CHECK (locked_amount >= 0),
  released_amount NUMERIC(20, 2) NOT NULL DEFAULT 0,
  refunded_amount NUMERIC(20, 2) NOT NULL DEFAULT 0,
  penalty_paid NUMERIC(20, 2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'locked' CHECK (status IN ('locked', 'released', 'refunded', 'depleted')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contract_delivery_ticks (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES negotiated_contracts(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('delivered', 'defaulted', 'partial')),
  quantity_delivered NUMERIC(20, 2) NOT NULL DEFAULT 0,
  credits_transferred NUMERIC(20, 2) NOT NULL DEFAULT 0,
  penalty_charged NUMERIC(20, 2) NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS supply_contracts_resource_idx ON supply_contracts(resource_type);
CREATE INDEX IF NOT EXISTS contract_escrow_vaults_contract_idx ON contract_escrow_vaults(contract_id);
CREATE INDEX IF NOT EXISTS contract_delivery_ticks_contract_day_idx ON contract_delivery_ticks(contract_id, game_day);

-- -----------------------------------------------------------------------------
-- Historical migration 027_planetary_map_and_territory_concessions.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 027: Interactive Planetary Regional Grid & Territory Concessions

CREATE TABLE IF NOT EXISTS planetary_regions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(140) NOT NULL,
    biome_type VARCHAR(64) NOT NULL,
    description TEXT NOT NULL,
    climate_status VARCHAR(64) NOT NULL DEFAULT 'optimal',
    base_solar_index NUMERIC(6, 2) NOT NULL DEFAULT 1.00,
    base_geothermal_index NUMERIC(6, 2) NOT NULL DEFAULT 1.00,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS territory_plots (
    id VARCHAR(64) PRIMARY KEY,
    region_id VARCHAR(64) NOT NULL REFERENCES planetary_regions(id) ON DELETE CASCADE,
    plot_name VARCHAR(140) NOT NULL,
    coord_x NUMERIC(6, 2) NOT NULL DEFAULT 0.00,
    coord_y NUMERIC(6, 2) NOT NULL DEFAULT 0.00,
    terrain_type VARCHAR(64) NOT NULL DEFAULT 'plains',
    primary_resource VARCHAR(32) NOT NULL DEFAULT 'energy',
    base_yield_rate NUMERIC(10, 2) NOT NULL DEFAULT 10.00,
    development_level INTEGER NOT NULL DEFAULT 1,
    max_level INTEGER NOT NULL DEFAULT 5,
    infrastructure_name VARCHAR(140) NOT NULL DEFAULT 'Standard Resource Rig',
    lease_holder_id VARCHAR(64) REFERENCES humans(id) ON DELETE SET NULL,
    daily_lease_fee NUMERIC(14, 2) NOT NULL DEFAULT 50.00,
    lease_expires_game_day INTEGER,
    accumulated_yield NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    last_harvested_game_day INTEGER,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS territory_plot_leases (
    id VARCHAR(64) PRIMARY KEY,
    plot_id VARCHAR(64) NOT NULL REFERENCES territory_plots(id) ON DELETE CASCADE,
    human_id VARCHAR(64) NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    corporation_id VARCHAR(64) REFERENCES corporations(id) ON DELETE SET NULL,
    starts_game_day INTEGER NOT NULL,
    expires_game_day INTEGER NOT NULL,
    total_paid NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS plot_yield_logs (
    id VARCHAR(64) PRIMARY KEY,
    plot_id VARCHAR(64) NOT NULL REFERENCES territory_plots(id) ON DELETE CASCADE,
    game_day INTEGER NOT NULL,
    resource_type VARCHAR(32) NOT NULL,
    amount_generated NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    fee_deducted NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_territory_plots_region ON territory_plots(region_id);
CREATE INDEX IF NOT EXISTS idx_territory_plots_lease_holder ON territory_plots(lease_holder_id);
CREATE INDEX IF NOT EXISTS idx_territory_plot_leases_plot ON territory_plot_leases(plot_id);
CREATE INDEX IF NOT EXISTS idx_plot_yield_logs_plot_day ON plot_yield_logs(plot_id, game_day);

-- Seed initial 6 Macro-Regions
INSERT INTO planetary_regions (id, name, biome_type, description, climate_status, base_solar_index, base_geothermal_index)
VALUES
('REG-PACIFIC-RIM', 'Pacific Rim Sprawl', 'coastal_megalopolis', 'Dense cybernetic coastal zones and high-throughput trade networks.', 'temperate', 1.15, 1.30),
('REG-SAHARAN-BASIN', 'Saharan Solar Basin', 'hyper_arid_desert', 'Massive photovoltaic and concentrated solar fields across the equator.', 'arid', 2.40, 0.85),
('REG-NORDIC-CRYO', 'Nordic Cryo Hub', 'sub_polar_tundra', 'Supercooled data clusters and geothermal power reservoirs in Scandinavian fjords.', 'frigid', 0.65, 1.80),
('REG-ATACAMA-CORRIDOR', 'Atacama Mineral Basin', 'high_altitude_plateau', 'Vast lithium salt flats and rare earth mineral extraction corridors.', 'arid', 1.85, 1.10),
('REG-EURO-ALPINE', 'Euro-Alpine Hydro Grid', 'alpine_montane', 'Hydroelectric cascade networks and high-precision quantum research labs.', 'temperate', 1.00, 1.05),
('REG-ORBITAL-RING', 'Low Orbit Tether Array', 'orbital_exosphere', 'Space elevator tether nodes and zero-gravity micro-fabrication platforms.', 'vacuum', 2.80, 0.00)
ON CONFLICT (id) DO NOTHING;

-- Seed initial Territory Plots
INSERT INTO territory_plots (id, region_id, plot_name, coord_x, coord_y, terrain_type, primary_resource, base_yield_rate, development_level, infrastructure_name, daily_lease_fee)
VALUES
('PLOT-PAC-01', 'REG-PACIFIC-RIM', 'Neo-Tokyo High-Bay Terminal', 139.69, 35.68, 'coastal', 'compute', 25.00, 2, 'Quantum Relay Server Bank', 75.00),
('PLOT-PAC-02', 'REG-PACIFIC-RIM', 'Yokohama Deepwater Dock', 139.63, 35.44, 'marine', 'energy', 30.00, 1, 'Tidal Surge Generator', 60.00),
('PLOT-PAC-03', 'REG-PACIFIC-RIM', 'Kanto Inland Fabrication Dome', 139.50, 35.90, 'urban', 'material', 20.00, 1, 'Automated Component Foundry', 50.00),
('PLOT-PAC-04', 'REG-PACIFIC-RIM', 'Fuji Geothermal Vent', 138.72, 35.36, 'volcanic', 'energy', 45.00, 3, 'Magma Tap Turbine', 120.00),

('PLOT-SAH-01', 'REG-SAHARAN-BASIN', 'Ksar Ghilane Mirror Array', 9.63, 32.98, 'dunes', 'energy', 60.00, 2, 'Concentrated Solar Tower', 90.00),
('PLOT-SAH-02', 'REG-SAHARAN-BASIN', 'Ahaggar High-Altitude Collector', 5.52, 23.28, 'rocky_desert', 'energy', 75.00, 3, 'Photovoltaic Glassfield', 140.00),
('PLOT-SAH-03', 'REG-SAHARAN-BASIN', 'Oasis Aeroponic Farm Ring', 8.12, 28.50, 'oasis', 'food', 35.00, 1, 'Deep Aquifer Biome Dome', 70.00),
('PLOT-SAH-04', 'REG-SAHARAN-BASIN', 'Reggane Silicon Quarry', 0.17, 26.71, 'gravel_desert', 'material', 30.00, 1, 'Silica Harvester Array', 65.00),

('PLOT-NOR-01', 'REG-NORDIC-CRYO', 'Svalbard Deep Glacial Vault', 15.46, 78.22, 'permafrost', 'compute', 50.00, 2, 'Sub-Zero Server Vault', 85.00),
('PLOT-NOR-02', 'REG-NORDIC-CRYO', 'Bergen Fjord Hydro Station', 5.32, 60.39, 'fjord', 'energy', 40.00, 2, 'Cascading Hydro Generator', 80.00),
('PLOT-NOR-03', 'REG-NORDIC-CRYO', 'Kiruna Sub-Crust Magnetite Mine', 20.22, 67.85, 'mountain', 'material', 55.00, 3, 'Heavy Bore Excavator', 110.00),
('PLOT-NOR-04', 'REG-NORDIC-CRYO', 'Tromsø Magnetic Observatory', 18.95, 69.64, 'arctic', 'compute', 30.00, 1, 'Aurora Sensor Cluster', 60.00),

('PLOT-ATA-01', 'REG-ATACAMA-CORRIDOR', 'Salar de Atacama Brine Fields', -68.25, -23.50, 'salt_flat', 'material', 70.00, 3, 'Lithium Evaporation Pan Array', 130.00),
('PLOT-ATA-02', 'REG-ATACAMA-CORRIDOR', 'Chajnantor High Sensor Array', -67.75, -23.02, 'high_altitude', 'compute', 40.00, 2, 'Sub-Millimeter Array Terminal', 90.00),
('PLOT-ATA-03', 'REG-ATACAMA-CORRIDOR', 'Antofagasta Coastal Smelter', -70.40, -23.65, 'coastal', 'material', 35.00, 1, 'Plasma Smelting Complex', 75.00),
('PLOT-ATA-04', 'REG-ATACAMA-CORRIDOR', 'Domeykos Solar Corridor', -69.10, -24.80, 'rocky_desert', 'energy', 50.00, 2, 'High-Irradiance PV Array', 95.00),

('PLOT-EUR-01', 'REG-EURO-ALPINE', 'Geneva Quantum Collider Hub', 6.14, 46.20, 'urban', 'compute', 45.00, 2, 'Sub-Atomic Accelerator Tap', 100.00),
('PLOT-EUR-02', 'REG-EURO-ALPINE', 'Rhone Valley Hydro Cascade', 7.36, 46.23, 'valley', 'energy', 35.00, 1, 'Alpine Reservoir Dam', 70.00),
('PLOT-EUR-03', 'REG-EURO-ALPINE', 'Bavarian Synthetic Food Silos', 11.58, 48.13, 'plains', 'food', 40.00, 2, 'Cellular Agriculture Facility', 80.00),
('PLOT-EUR-04', 'REG-EURO-ALPINE', 'Ruhr Automated Metal Foundry', 7.01, 51.45, 'industrial', 'material', 45.00, 2, 'Recycled Alloy Forge', 90.00),

('PLOT-ORB-01', 'REG-ORBITAL-RING', 'Quito Space Elevator Anchor', -78.46, -0.18, 'equatorial_peak', 'energy', 80.00, 3, 'Carbon Nanotube Power Link', 180.00),
('PLOT-ORB-02', 'REG-ORBITAL-RING', 'Kilimanjaro Sky Hook Station', 37.35, -3.06, 'equatorial_peak', 'material', 65.00, 2, 'Orbital Freight Launcher', 150.00),
('PLOT-ORB-03', 'REG-ORBITAL-RING', 'Zenith Zero-G Fabrication Ring', 0.00, 0.00, 'orbital', 'material', 90.00, 4, 'Microgravity Crucible', 220.00),
('PLOT-ORB-04', 'REG-ORBITAL-RING', 'Solar Lagrange Concentrator', 0.00, 0.00, 'orbital', 'energy', 100.00, 4, 'Orbital Microwave Emitter', 250.00)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 028_dynasty_lineage_and_heirlooms.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 028: Dynastic Lineage Tree, Heritage Traits & Heirlooms Archive
-- Supports multi-generational lineage tracking, dynastic perks, and equipable family heirlooms.

create table if not exists dynasties (
  id text primary key,
  email text not null unique,
  dynasty_name text not null,
  motto text not null default 'Labor Omnia Vincit',
  founder_human_id text references humans(id),
  legacy_points integer not null default 0,
  total_wealth_generated numeric(20,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists dynasty_lineage_records (
  id text primary key,
  dynasty_id text not null references dynasties(id) on delete cascade,
  human_id text not null references humans(id),
  predecessor_human_id text references humans(id),
  generation integer not null default 1,
  name text not null,
  title text not null default 'Dynastic Heir',
  birth_game_day bigint not null default 1,
  death_game_day bigint,
  is_incumbent boolean not null default false,
  cause_of_death text,
  epitaph text,
  lifetime_wealth numeric(20,2) not null default 0,
  businesses_founded integer not null default 0,
  proposals_authored integer not null default 0,
  legacy_score integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists dynasty_perks (
  id text primary key,
  dynasty_id text not null references dynasties(id) on delete cascade,
  perk_key text not null,
  perk_name text not null,
  perk_category text not null,
  tier integer not null default 1,
  unlocked_game_day bigint not null default 1,
  created_at timestamptz not null default now(),
  constraint uq_dynasty_perk unique (dynasty_id, perk_key)
);

create table if not exists dynasty_heirlooms (
  id text primary key,
  dynasty_id text not null references dynasties(id) on delete cascade,
  name text not null,
  heirloom_type text not null check (heirloom_type in ('founder_seal', 'senate_gavel', 'quantum_cipher', 'pioneer_chronometer', 'dynasty_standard')),
  quality_tier text not null default 'Legendary',
  stat_buff text not null,
  equipped_by_human_id text references humans(id),
  inscription text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_dynasties_email on dynasties(email);
create index if not exists idx_dynasty_lineage_records_dynasty on dynasty_lineage_records(dynasty_id, generation asc);
create index if not exists idx_dynasty_lineage_records_human on dynasty_lineage_records(human_id);
create index if not exists idx_dynasty_perks_dynasty on dynasty_perks(dynasty_id);
create index if not exists idx_dynasty_heirlooms_dynasty on dynasty_heirlooms(dynasty_id);

-- Seed founding dynasty and lineage for player H-0044 (Amara Vance) if exists
insert into dynasties (id, email, dynasty_name, motto, founder_human_id, legacy_points, total_wealth_generated)
values (
  'DYN-H0044',
  'amara@earth.local',
  'House Vance',
  'From the Red Dust We Build Eternity',
  'H-0044',
  350,
  450000.00
) on conflict (email) do nothing;

insert into dynasty_lineage_records (
  id, dynasty_id, human_id, predecessor_human_id, generation, name, title,
  birth_game_day, death_game_day, is_incumbent, cause_of_death, epitaph,
  lifetime_wealth, businesses_founded, proposals_authored, legacy_score
) values
(
  'LIN-001',
  'DYN-H0044',
  'H-0044',
  null,
  1,
  'Cassian Vance I',
  'Pioneer Patriarch',
  1,
  140,
  false,
  'Hyperbaric Decompression',
  'Laid the foundation stones of Neo-Tokyo and the first Quantum Relay Network.',
  280000.00,
  3,
  4,
  180
),
(
  'LIN-002',
  'DYN-H0044',
  'H-0044',
  'H-0044',
  2,
  'Amara Vance',
  'Current Dynastic Head',
  120,
  null,
  true,
  null,
  'Steering House Vance through the corporate expansion age.',
  170000.00,
  2,
  2,
  170
) on conflict (id) do nothing;

insert into dynasty_perks (id, dynasty_id, perk_key, perk_name, perk_category, tier, unlocked_game_day)
values
(
  'PRK-001',
  'DYN-H0044',
  'industrialist_lineage',
  'Industrialist Lineage',
  'operations',
  1,
  140
) on conflict (dynasty_id, perk_key) do nothing;

insert into dynasty_heirlooms (id, dynasty_id, name, heirloom_type, quality_tier, stat_buff, equipped_by_human_id, inscription)
values
(
  'HLM-001',
  'DYN-H0044',
  'The Vance Founding Signet',
  'founder_seal',
  'Legendary',
  '+10% Machine Build Speed & -15% Business Startup Fees',
  'H-0044',
  'Forged from the first batch of refined titanium produced by Pacific Rim Sprawl.'
),
(
  'HLM-002',
  'DYN-H0044',
  'High Senate Chronometer',
  'pioneer_chronometer',
  'Epic',
  '+12% Voting Weight in World Senate Injunctions',
  null,
  'Awarded for drafting the Constitutional Protection Charter on Game Day 75.'
) on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 029_commodity_futures_and_candlestick_history.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 029: Commodity Futures, Financial Derivatives & OHLC Candlestick Snapshots
-- Supports forward hedging contracts, locked collateral escrow, and historical market OHLC price charts.

create table if not exists commodity_futures_contracts (
  id text primary key,
  seller_human_id text not null references humans(id),
  buyer_human_id text references humans(id),
  commodity text not null check (commodity in ('energy', 'material', 'compute', 'food')),
  contract_size numeric(20,2) not null check (contract_size > 0),
  strike_price numeric(20,2) not null check (strike_price > 0),
  expiry_game_day bigint not null check (expiry_game_day > 0),
  collateral_locked numeric(20,2) not null default 0,
  premium_paid numeric(20,2) not null default 0,
  status text not null default 'open' check (status in ('open', 'matched', 'settled', 'defaulted', 'cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists market_ohlc_snapshots (
  id text primary key,
  commodity text not null check (commodity in ('energy', 'material', 'compute', 'food')),
  game_day bigint not null check (game_day > 0),
  open_price numeric(20,2) not null,
  high_price numeric(20,2) not null,
  low_price numeric(20,2) not null,
  close_price numeric(20,2) not null,
  volume numeric(20,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint uq_market_ohlc unique (commodity, game_day)
);

create index if not exists idx_commodity_futures_status on commodity_futures_contracts(commodity, status, expiry_game_day asc);
create index if not exists idx_commodity_futures_seller on commodity_futures_contracts(seller_human_id);
create index if not exists idx_commodity_futures_buyer on commodity_futures_contracts(buyer_human_id);
create index if not exists idx_market_ohlc_commodity_day on market_ohlc_snapshots(commodity, game_day desc);

-- Seed historical 30-day OHLC series for all 4 commodities up to day 185
do $$
declare
  commodities text[] := array['energy', 'material', 'compute', 'food'];
  base_prices numeric[] := array[30.00, 45.00, 60.00, 20.00];
  c text;
  idx int;
  day int;
  base_p numeric;
  o numeric;
  h numeric;
  l numeric;
  cls numeric;
  vol numeric;
  step_noise numeric;
begin
  for idx in 1..4 loop
    c := commodities[idx];
    base_p := base_prices[idx];
    for day in 155..185 loop
      step_noise := ((sin(day * 0.4 + idx) * 3.5) + (cos(day * 0.15) * 2.0))::numeric;
      o := round((base_p + step_noise)::numeric, 2);
      cls := round((o + (sin(day * 0.7) * 2.2)::numeric)::numeric, 2);
      h := round((greatest(o, cls) + (abs(cos(day * 0.3)) * 2.0 + 0.5)::numeric)::numeric, 2);
      l := round((least(o, cls) - (abs(sin(day * 0.5)) * 1.8 + 0.3)::numeric)::numeric, 2);
      vol := round((1000.0 + (abs(sin(day * 0.9)) * 1500.0)::numeric)::numeric, 0);

      insert into market_ohlc_snapshots (id, commodity, game_day, open_price, high_price, low_price, close_price, volume)
      values (
        'OHLC-' || upper(c) || '-' || day,
        c,
        day,
        o,
        h,
        l,
        cls,
        vol
      ) on conflict (commodity, game_day) do nothing;
    end loop;
  end loop;
end $$;

-- Seed sample open and active futures contracts for player H-0044 if humans exist
do $$
begin
  if exists (select 1 from humans where id = 'H-0044') then
    insert into commodity_futures_contracts (
      id, seller_human_id, buyer_human_id, commodity, contract_size, strike_price, expiry_game_day, collateral_locked, premium_paid, status
    ) values
    (
      'FUT-ENERGY-101',
      'H-0044',
      null,
      'energy',
      250.00,
      28.50,
      210,
      250.00,
      0.00,
      'open'
    ) on conflict (id) do nothing;
  end if;

  if exists (select 1 from humans where id = 'H-0044') and exists (select 1 from humans where id = 'H-0045') then
    insert into commodity_futures_contracts (
      id, seller_human_id, buyer_human_id, commodity, contract_size, strike_price, expiry_game_day, collateral_locked, premium_paid, status
    ) values
    (
      'FUT-COMPUTE-102',
      'H-0045',
      'H-0044',
      'compute',
      100.00,
      58.00,
      200,
      100.00,
      250.00,
      'matched'
    ) on conflict (id) do nothing;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Historical migration 030_net_worth_snapshots_and_asset_history.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 030: Net Worth Snapshots, Multi-Asset Allocation & Financial History
-- Tracks 4-pillar asset portfolios (Liquid Credits, Commodities, Corporate Equity, Real Estate Concessions).

create table if not exists net_worth_snapshots (
  id text primary key,
  human_id text not null references humans(id),
  game_day bigint not null check (game_day > 0),
  liquid_credits numeric(20,2) not null default 0,
  commodity_valuation numeric(20,2) not null default 0,
  equity_valuation numeric(20,2) not null default 0,
  real_estate_valuation numeric(20,2) not null default 0,
  total_net_worth numeric(20,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint uq_net_worth_human_day unique (human_id, game_day)
);

create index if not exists idx_net_worth_human_day on net_worth_snapshots(human_id, game_day desc);

-- Seed 30-day historical net-worth trajectory for founding player H-0044
do $$
declare
  day int;
  base_cash numeric := 15000.00;
  base_comm numeric := 8000.00;
  base_eq numeric := 25000.00;
  base_re numeric := 12000.00;
  c_val numeric;
  m_val numeric;
  e_val numeric;
  r_val numeric;
  tot numeric;
begin
  if exists (select 1 from humans where id = 'H-0044') then
    for day in 155..185 loop
      c_val := round((base_cash + ((day - 155) * 850.00) + (sin(day * 0.5) * 1200.00)::numeric)::numeric, 2);
      m_val := round((base_comm + ((day - 155) * 420.00) + (cos(day * 0.3) * 800.00)::numeric)::numeric, 2);
      e_val := round((base_eq + ((day - 155) * 1450.00) + (sin(day * 0.8) * 2500.00)::numeric)::numeric, 2);
      r_val := round((base_re + ((day - 155) * 600.00))::numeric, 2);
      tot := c_val + m_val + e_val + r_val;

      insert into net_worth_snapshots (
        id, human_id, game_day, liquid_credits, commodity_valuation, equity_valuation, real_estate_valuation, total_net_worth
      ) values (
        'NW-H0044-' || day,
        'H-0044',
        day,
        c_val,
        m_val,
        e_val,
        r_val,
        tot
      ) on conflict (human_id, game_day) do update set
        liquid_credits = excluded.liquid_credits,
        commodity_valuation = excluded.commodity_valuation,
        equity_valuation = excluded.equity_valuation,
        real_estate_valuation = excluded.real_estate_valuation,
        total_net_worth = excluded.total_net_worth;
    end loop;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Historical migration 031_auth_email_delivery_observability.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_email_deliveries (
  id TEXT PRIMARY KEY,
  correlation_id TEXT NOT NULL,
  human_id TEXT NOT NULL,
  recipient_masked TEXT NOT NULL,
  action TEXT NOT NULL,
  status TEXT NOT NULL,
  provider_message_id TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auth_email_deliveries_created ON auth_email_deliveries (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_email_deliveries_correlation ON auth_email_deliveries (correlation_id);

-- -----------------------------------------------------------------------------
-- Historical migration 032_social_gameplay.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Formal social gameplay: alliances, negotiations, campaigns, announcements,
-- lobbying, shared projects, and diplomatic agreements.
CREATE TABLE IF NOT EXISTS social_initiatives (
  id TEXT PRIMARY KEY,
  creator_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  target_human_id TEXT REFERENCES humans(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('alliance','negotiation','campaign','announcement','lobbying','shared_project','agreement')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','active','accepted','declined','completed','expired')),
  terms JSONB NOT NULL DEFAULT '{}'::jsonb,
  deadline_game_day INT,
  escrow_amount NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (escrow_amount >= 0),
  escrow_status TEXT NOT NULL DEFAULT 'none' CHECK (escrow_status IN ('none','locked','released','forfeited')),
  reputation_delta INT NOT NULL DEFAULT 0,
  progress INT NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  game_day INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS social_initiative_members (
  initiative_id TEXT NOT NULL REFERENCES social_initiatives(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'participant',
  status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','accepted','declined','completed')),
  contribution INT NOT NULL DEFAULT 0,
  PRIMARY KEY (initiative_id, human_id)
);
CREATE INDEX IF NOT EXISTS social_initiatives_participant_idx ON social_initiative_members(human_id, status);
CREATE INDEX IF NOT EXISTS social_initiatives_kind_status_idx ON social_initiatives(kind, status, game_day DESC);

-- -----------------------------------------------------------------------------
-- Historical migration 033_social_relationships_timeline.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS social_relationships (
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  other_human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  trust INT NOT NULL DEFAULT 0,
  public_reputation INT NOT NULL DEFAULT 0,
  completed_agreements INT NOT NULL DEFAULT 0,
  broken_commitments INT NOT NULL DEFAULT 0,
  last_interaction_game_day INT,
  PRIMARY KEY (human_id, other_human_id),
  CHECK (human_id <> other_human_id)
);
CREATE INDEX IF NOT EXISTS social_relationships_trust_idx ON social_relationships(human_id, trust DESC);

-- -----------------------------------------------------------------------------
-- Historical migration 034_remove_planetary_map.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 034: Remove the unused planetary map and territory concession subsystem.
-- Keep migration 027 in history; this forward migration is safe for existing databases.
-- This migration intentionally uses DROP DDL rather than CREATE/ALTER DDL.
DROP TABLE IF EXISTS plot_yield_logs CASCADE;
DROP TABLE IF EXISTS territory_plot_leases CASCADE;
DROP TABLE IF EXISTS territory_plots CASCADE;
DROP TABLE IF EXISTS planetary_regions CASCADE;

-- -----------------------------------------------------------------------------
-- Historical migration 035_ensure_components_market.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Keep the Components commodity available for existing production databases
-- created before the market catalog included it.
INSERT INTO market_prices (product, price, supply, demand, game_day)
SELECT 'components', 118.70, 186, 276, game_day
FROM world_state
WHERE id = 'WORLD'
  AND NOT EXISTS (
    SELECT 1 FROM market_prices WHERE product = 'components'
  );

-- -----------------------------------------------------------------------------
-- Historical migration 036_components_market_history.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Give Components the same persistent price-history coverage as the other
-- commodities so the spot-market chart is meaningful for every listed row.
alter table market_ohlc_snapshots
  drop constraint if exists market_ohlc_snapshots_commodity_check;

alter table market_ohlc_snapshots
  add constraint market_ohlc_snapshots_commodity_check
  check (commodity in ('energy', 'material', 'compute', 'food', 'components'));

with current_world as (
  select game_day from world_state where id = 'WORLD'
), series as (
  select current_world.game_day + offset_day as game_day, offset_day
  from current_world cross join generate_series(-29, 0) as offset_day
), prices as (
  select
    game_day,
    round((118.70 + sin(game_day * 0.37) * 8.40 + cos(game_day * 0.11) * 3.10)::numeric, 2) as open_price,
    round((118.70 + sin(game_day * 0.37) * 8.40 + cos(game_day * 0.11) * 3.10 + sin(game_day * 0.71) * 4.60)::numeric, 2) as close_price,
    offset_day
  from series
)
insert into market_ohlc_snapshots (
  id, commodity, game_day, open_price, high_price, low_price, close_price, volume
)
select
  'OHLC-COMPONENTS-' || game_day,
  'components',
  game_day,
  open_price,
  round((greatest(open_price, close_price) + 2.40)::numeric, 2),
  round((least(open_price, close_price) - 2.10)::numeric, 2),
  close_price,
  round((900 + abs(sin(game_day * 0.53)) * 1800)::numeric, 0)
from prices
on conflict (commodity, game_day) do nothing;

-- -----------------------------------------------------------------------------
-- Historical migration 037_continuous_engine_schema.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 037: Add columns and tables required by continuous simulation engines
-- This migration adds schema elements that the server-side continuous engines
-- (production, technology, financial, institutions, lifecycle) require.

BEGIN;

-- 1. research_projects: add updated_at for tracking last engine settlement
ALTER TABLE research_projects
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 2. technologies: add status column for patent lifecycle tracking
ALTER TABLE technologies
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'available'
  CHECK (status IN ('available', 'researching', 'patented', 'obsolete'));

-- 3. machines: add focus column for production output/input modifiers
ALTER TABLE machines
  ADD COLUMN IF NOT EXISTS focus TEXT NOT NULL DEFAULT 'efficiency'
  CHECK (focus IN ('efficiency', 'durability', 'safety', 'cost'));

-- 4. cities: add status column for active/suspended/dissolved tracking
ALTER TABLE cities
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
  CHECK (status IN ('active', 'suspended', 'dissolved'));

-- 5. proposals: add updated_at for tracking engine settlement timestamps
ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 6. technology_events: audit trail for R&D milestones and royalty payments
CREATE TABLE IF NOT EXISTS technology_events (
  id          TEXT PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technologies(id),
  event_type  TEXT NOT NULL CHECK (event_type IN ('royalty_payment', 'patent_granted', 'research_started', 'research_completed', 'license_granted')),
  actor_id    TEXT NOT NULL REFERENCES humans(id),
  target_id   TEXT REFERENCES humans(id),
  details     TEXT NOT NULL DEFAULT '{}',
  game_day    BIGINT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS technology_events_tech_idx ON technology_events(technology_id, game_day DESC);
CREATE INDEX IF NOT EXISTS technology_events_actor_idx ON technology_events(actor_id, game_day DESC);

COMMIT;

-- -----------------------------------------------------------------------------
-- Historical migration 038_seed_canonical_institutions.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 038: complete the canonical local institution seed rows.
-- The institutions table alone is insufficient for city/corporation foreign keys.

INSERT INTO institutions (id, kind, name, status)
VALUES
  ('CITY-0084', 'CITY', 'New Carthage', 'active'),
  ('CORP-001', 'CORPORATION', 'Helios Cooperative', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury)
VALUES ('CITY-0084', 'CITY-0084', 0, 100, 100, 100, 50, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO corporations (id, institution_id, member_count, treasury, constitution_version)
VALUES ('CORP-001', 'CORP-001', 0, 0, 1)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 039_seed_market_catalog.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Keep the market catalog complete for existing installations.
-- Orders may remain open until a later batch settlement, but every supported
-- product needs a price row so it can be displayed and settled.
INSERT INTO market_prices (product, price, supply, demand, game_day)
SELECT seed.product, seed.price, seed.supply, seed.demand, world.game_day
FROM (VALUES
  ('food', 20.00, 700, 620),
  ('material', 45.00, 1200, 900),
  ('components', 118.70, 186, 276),
  ('energy', 30.00, 900, 820),
  ('compute', 60.00, 480, 360)
) AS seed(product, price, supply, demand)
CROSS JOIN world_state AS world
WHERE world.id = 'WORLD'
ON CONFLICT (product) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 040_enable_food_market.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Food is a first-class market commodity, including deferred limit orders.
ALTER TABLE market_orders DROP CONSTRAINT IF EXISTS market_orders_product_check;
ALTER TABLE market_orders ADD CONSTRAINT market_orders_product_check
  CHECK (product IN ('food', 'material', 'components', 'energy', 'compute'));

INSERT INTO market_prices (product, price, supply, demand, game_day)
SELECT 'food', 20.00, 700, 620, game_day
FROM world_state
WHERE id = 'WORLD'
  AND NOT EXISTS (SELECT 1 FROM market_prices WHERE product = 'food');

-- -----------------------------------------------------------------------------
-- Historical migration 041_business_workforce.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Staff are business assets with wages, skills, and morale. They make the
-- management loop about people as well as machines.
CREATE TABLE IF NOT EXISTS business_employees (
  id text primary key,
  business_id text not null references businesses(id) on delete cascade,
  name text not null,
  role text not null,
  skill numeric(5,2) not null default 0.60 check (skill >= 0 and skill <= 1),
  morale numeric(5,2) not null default 0.75 check (morale >= 0 and morale <= 1),
  wage numeric(20,2) not null default 40 check (wage >= 0),
  status text not null default 'active' check (status in ('active','leave','dismissed')),
  hired_game_day bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS business_employees_business_idx
  ON business_employees(business_id, status);

INSERT INTO business_employees (id, business_id, name, role, skill, morale, wage, hired_game_day)
SELECT 'EMP-' || substr(md5(b.id || seed.role), 1, 12), b.id, seed.name, seed.role,
       seed.skill, seed.morale, seed.wage, COALESCE(w.game_day, 1)
FROM businesses b
CROSS JOIN (VALUES
  ('Mara Voss', 'Operations Lead', 0.82, 0.80, 85.00),
  ('Ilan Roe', 'Systems Technician', 0.71, 0.76, 62.00),
  ('Nia Sol', 'Client Coordinator', 0.66, 0.84, 54.00)
) AS seed(name, role, skill, morale, wage)
LEFT JOIN world_state w ON w.id = 'WORLD'
WHERE NOT EXISTS (
  SELECT 1 FROM business_employees e WHERE e.business_id = b.id
);

-- -----------------------------------------------------------------------------
-- Historical migration 042_link_cities_to_corporations.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 042: make the canonical city/corporation affiliation explicit.
-- Existing city membership remains intact; this only links the seeded city
-- to the seeded corporation so residency can carry corporation membership.

ALTER TABLE cities
  ADD COLUMN IF NOT EXISTS corporation_id TEXT REFERENCES corporations(id);

UPDATE cities
SET corporation_id = 'CORP-001'
WHERE id = 'CITY-0084'
  AND corporation_id IS NULL
  AND EXISTS (SELECT 1 FROM corporations WHERE id = 'CORP-001');

-- -----------------------------------------------------------------------------
-- Historical migration 043_corporation_shared_technology.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Corporation research commons: patented technologies may be shared with the
-- inventor's corporation and used by its members without an external license fee.

CREATE TABLE IF NOT EXISTS corporation_technology_shares (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  patent_id TEXT NOT NULL REFERENCES patents(id),
  shared_by_human_id TEXT NOT NULL REFERENCES humans(id),
  shared_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_corporation_shared_patent UNIQUE (corporation_id, patent_id)
);

CREATE INDEX IF NOT EXISTS corporation_technology_shares_member_idx
  ON corporation_technology_shares(corporation_id, status);

-- -----------------------------------------------------------------------------
-- Historical migration 044_enable_food_production_events.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 044: Make food production a first-class event
ALTER TABLE production_events DROP CONSTRAINT IF EXISTS production_events_resource_check;
ALTER TABLE production_events
  ADD CONSTRAINT production_events_resource_check
  CHECK (resource IN ('food', 'material', 'components', 'energy', 'compute'));

-- -----------------------------------------------------------------------------
-- Historical migration 045_business_attribution_for_technology_licenses.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
ALTER TABLE technology_licenses
  ADD COLUMN IF NOT EXISTS licensee_business_id TEXT REFERENCES businesses(id);

CREATE INDEX IF NOT EXISTS technology_licenses_business_idx
  ON technology_licenses(licensee_business_id, status);

-- -----------------------------------------------------------------------------
-- Historical migration 046_business_technology_adoption.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- A completed capability is researched globally, but each business chooses
-- when to deploy it at its workplace.
CREATE TABLE IF NOT EXISTS business_technology_adoptions (
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  technology_id TEXT NOT NULL REFERENCES technologies(id) ON DELETE CASCADE,
  adopted_by TEXT NOT NULL REFERENCES humans(id),
  adopted_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'withdrawn')),
  PRIMARY KEY (business_id, technology_id)
);

CREATE INDEX IF NOT EXISTS business_technology_adoptions_technology_idx
  ON business_technology_adoptions(technology_id, status);

-- -----------------------------------------------------------------------------
-- Historical migration 047_institution_charter_rules.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 047: add institution-level charter storage for existing databases.
-- City and corporation rules are stored on the shared institution record so
-- world snapshots, tax settlement, and market rules can read them uniformly.

ALTER TABLE institutions
  ADD COLUMN IF NOT EXISTS charter_rules TEXT;

-- -----------------------------------------------------------------------------
-- Historical migration 048_corporation_membership_policy.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 048: corporation admission policy and explicit capital city.

ALTER TABLE corporations
  ADD COLUMN IF NOT EXISTS capital_city_id TEXT REFERENCES cities(id),
  ADD COLUMN IF NOT EXISTS admission_policy TEXT NOT NULL DEFAULT 'open'
    CHECK (admission_policy IN ('open', 'approval'));

UPDATE corporations c
SET capital_city_id = source.city_id
FROM (
  SELECT corporation_id, MIN(id) AS city_id
  FROM cities
  WHERE corporation_id IS NOT NULL
  GROUP BY corporation_id
) AS source
WHERE c.id = source.corporation_id
  AND c.capital_city_id IS NULL;

CREATE TABLE IF NOT EXISTS corporation_membership_requests (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_game_day BIGINT NOT NULL,
  decided_game_day BIGINT,
  decided_by TEXT REFERENCES humans(id),
  UNIQUE (corporation_id, human_id, status)
);

CREATE INDEX IF NOT EXISTS corporation_membership_requests_corporation_idx
  ON corporation_membership_requests(corporation_id, status, requested_game_day);

CREATE INDEX IF NOT EXISTS corporation_membership_requests_human_idx
  ON corporation_membership_requests(human_id, status, requested_game_day);

-- -----------------------------------------------------------------------------
-- Historical migration 049_community_management_and_roles.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 049: Community descriptions, admission policies, role management, and membership requests.

ALTER TABLE communities
  ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS admission_policy TEXT NOT NULL DEFAULT 'open'
    CHECK (admission_policy IN ('open', 'approval'));

-- Allow 'admin' role in community_members
ALTER TABLE community_members DROP CONSTRAINT IF EXISTS community_members_role_check;
ALTER TABLE community_members ADD CONSTRAINT community_members_role_check CHECK (role IN ('founder', 'admin', 'member'));

CREATE TABLE IF NOT EXISTS community_membership_requests (
  id TEXT PRIMARY KEY,
  community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_game_day BIGINT NOT NULL,
  decided_game_day BIGINT,
  decided_by TEXT REFERENCES humans(id),
  UNIQUE (community_id, human_id, status)
);

CREATE INDEX IF NOT EXISTS community_membership_requests_comm_idx
  ON community_membership_requests(community_id, status, requested_game_day);

CREATE INDEX IF NOT EXISTS community_membership_requests_human_idx
  ON community_membership_requests(human_id, status, requested_game_day);

-- -----------------------------------------------------------------------------
-- Historical migration 050_real_estate_and_municipal_labor.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 050: Physical Real Estate, Multi-Tier Buildings, Municipal Shared Shift Labor Pool, and Corporate R&D Commons

CREATE TABLE IF NOT EXISTS buildings (
  id TEXT PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  owner_id TEXT NOT NULL,
  ownership_type TEXT NOT NULL CHECK (ownership_type IN ('private', 'municipal', 'corporate')),
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  building_type TEXT NOT NULL,
  name TEXT NOT NULL,
  tier INTEGER NOT NULL DEFAULT 1 CHECK (tier >= 1 AND tier <= 5),
  condition NUMERIC(5,2) NOT NULL DEFAULT 100 CHECK (condition >= 0 AND condition <= 100),
  max_staff_slots INTEGER NOT NULL DEFAULT 4,
  upkeep_energy NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_food NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_materials NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_components NUMERIC(10,2) NOT NULL DEFAULT 0,
  upkeep_compute NUMERIC(10,2) NOT NULL DEFAULT 0,
  base_revenue_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'under_construction', 'damaged', 'closed')),
  created_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS buildings_city_idx ON buildings(city_id, status);
CREATE INDEX IF NOT EXISTS buildings_owner_idx ON buildings(owner_id, status);
CREATE INDEX IF NOT EXISTS buildings_business_idx ON buildings(business_id);

CREATE TABLE IF NOT EXISTS building_staff_assignments (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  staff_type TEXT NOT NULL CHECK (staff_type IN ('machine', 'employee')),
  machine_id TEXT REFERENCES machines(id) ON DELETE CASCADE,
  employee_id TEXT REFERENCES business_employees(id) ON DELETE CASCADE,
  assigned_by TEXT NOT NULL REFERENCES humans(id),
  assigned_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'reassigned')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_building_machine_slot UNIQUE (building_id, machine_id)
);

CREATE INDEX IF NOT EXISTS building_staff_building_idx ON building_staff_assignments(building_id, status);

CREATE TABLE IF NOT EXISTS municipal_labor_pool (
  id TEXT PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  registered_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'withdrawn')),
  accumulated_wages_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_municipal_machine UNIQUE (city_id, machine_id)
);

CREATE INDEX IF NOT EXISTS municipal_labor_city_idx ON municipal_labor_pool(city_id, status);
CREATE INDEX IF NOT EXISTS municipal_labor_human_idx ON municipal_labor_pool(human_id, status);

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
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_corp_tech_pool UNIQUE (corporation_id, technology_key)
);

CREATE INDEX IF NOT EXISTS corporate_research_corp_idx ON corporate_research_pools(corporation_id, status);

-- Seed Initial Municipal Megaprojects for Canonical Cities
INSERT INTO buildings (id, city_id, owner_id, ownership_type, building_type, name, tier, condition, max_staff_slots, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, base_revenue_crd, status, created_game_day)
SELECT 'BLD-MUNI-GEO-0084', 'CITY-0084', 'CITY-0084', 'municipal', 'geothermal-grid', 'New Carthage Central Geothermal Grid', 3, 98.0, 12, 0.0, 0.0, 1.5, 0.5, 0.2, 850.0, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM buildings WHERE id = 'BLD-MUNI-GEO-0084');

INSERT INTO buildings (id, city_id, owner_id, ownership_type, building_type, name, tier, condition, max_staff_slots, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, base_revenue_crd, status, created_game_day)
SELECT 'BLD-MUNI-LOG-0084', 'CITY-0084', 'CITY-0084', 'municipal', 'transit-terminus', 'New Carthage Central Transit Hub', 2, 95.0, 16, 2.0, 0.0, 0.5, 0.8, 0.5, 1200.0, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM buildings WHERE id = 'BLD-MUNI-LOG-0084');

INSERT INTO buildings (id, city_id, owner_id, ownership_type, building_type, name, tier, condition, max_staff_slots, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, base_revenue_crd, status, created_game_day)
SELECT 'BLD-MUNI-HOSP-0084', 'CITY-0084', 'CITY-0084', 'municipal', 'general-hospital', 'New Carthage Metropolitan Medical Center', 2, 99.0, 10, 3.0, 1.5, 0.2, 1.0, 1.0, 600.0, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM buildings WHERE id = 'BLD-MUNI-HOSP-0084');

-- Seed Starter Corporate Research Projects
INSERT INTO corporate_research_pools (id, corporation_id, technology_key, name, target_compute, target_credits, contributed_compute, contributed_credits, status, started_game_day)
SELECT 'CRP-CORP001-AUTO', 'CORP-001', 'automated_assembly_v2', 'Automated Molecular Assembly 2.0', 5000, 25000, 1200, 8500, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM corporate_research_pools WHERE id = 'CRP-CORP001-AUTO');

INSERT INTO corporate_research_pools (id, corporation_id, technology_key, name, target_compute, target_credits, contributed_compute, contributed_credits, status, started_game_day)
SELECT 'CRP-CORP001-ORBIT', 'CORP-001', 'orbital_logistics_v2', 'Orbital Heavy Logistics & Skyhook Grid', 8000, 45000, 2100, 15000, 'active', 1
WHERE NOT EXISTS (SELECT 1 FROM corporate_research_pools WHERE id = 'CRP-CORP001-ORBIT');

-- -----------------------------------------------------------------------------
-- Historical migration 051_building_centric_urban_economy.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 051: Building-Centric Urban Economy, Slot Footprints, Public Investment Shares, and Civic Dividend Payouts

-- 1. Alter buildings table with self-contained economic and urban zoning attributes
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS slot_footprint INTEGER NOT NULL DEFAULT 1 CHECK (slot_footprint >= 1 AND slot_footprint <= 8);
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS ownership_class TEXT NOT NULL DEFAULT 'private' CHECK (ownership_class IN ('private', 'civic', 'public_investment'));
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS operating_policy TEXT NOT NULL DEFAULT 'balanced' CHECK (operating_policy IN ('balanced', 'high_output', 'eco_reserve', 'overclock'));
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS auto_repair_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS resource_output_type TEXT DEFAULT 'credits';
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS resource_output_amount NUMERIC(15,2) NOT NULL DEFAULT 0;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS daily_operating_credits NUMERIC(15,2) NOT NULL DEFAULT 0;

-- Update existing canonical buildings with appropriate slot footprints and ownership classes
UPDATE buildings SET slot_footprint = 6, ownership_class = 'civic', resource_output_type = 'energy', resource_output_amount = 25.0 WHERE id = 'BLD-MUNI-GEO-0084';
UPDATE buildings SET slot_footprint = 4, ownership_class = 'civic', resource_output_type = 'credits', resource_output_amount = 1200.0 WHERE id = 'BLD-MUNI-LOG-0084';
UPDATE buildings SET slot_footprint = 3, ownership_class = 'civic', resource_output_type = 'credits', resource_output_amount = 600.0 WHERE id = 'BLD-MUNI-HOSP-0084';

-- 2. Public Investment Megaproject Shares (Crowdfunding & Pro-Rata Dividends)
CREATE TABLE IF NOT EXISTS building_investment_shares (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  investor_id TEXT NOT NULL REFERENCES humans(id),
  shares_owned INTEGER NOT NULL CHECK (shares_owned > 0),
  total_shares_issued INTEGER NOT NULL CHECK (total_shares_issued > 0),
  invested_credits NUMERIC(20,2) NOT NULL DEFAULT 0,
  accumulated_dividends_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_building_investor UNIQUE (building_id, investor_id)
);

CREATE INDEX IF NOT EXISTS building_shares_building_idx ON building_investment_shares(building_id);
CREATE INDEX IF NOT EXISTS building_shares_investor_idx ON building_investment_shares(investor_id);

-- 3. Civic Dividend Payout Ledger
CREATE TABLE IF NOT EXISTS civic_dividend_payouts (
  id TEXT PRIMARY KEY,
  city_id TEXT NOT NULL REFERENCES cities(id),
  day BIGINT NOT NULL,
  total_civic_surplus NUMERIC(20,2) NOT NULL DEFAULT 0,
  base_dividend_per_resident NUMERIC(20,2) NOT NULL DEFAULT 0,
  participation_dividend_pool NUMERIC(20,2) NOT NULL DEFAULT 0,
  eligible_residents_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS civic_dividends_city_day_idx ON civic_dividend_payouts(city_id, day);

-- 4. Clean up legacy staff and machine assignments
DROP TABLE IF EXISTS building_staff_assignments CASCADE;
DROP TABLE IF EXISTS municipal_labor_pool CASCADE;

-- -----------------------------------------------------------------------------
-- Historical migration 052_patents_buildings_licensing_integration.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 052: Corporate Patents & Building Licensing Integration
-- Supports 3-tier licensing (Corporate Member, Private Building, City-Wide Civic),
-- transparent prerequisite gating, recurring royalties, and non-punitive expiration.

CREATE TABLE IF NOT EXISTS building_patent_licenses (
  id TEXT PRIMARY KEY,
  patent_id TEXT NOT NULL,
  patent_name TEXT NOT NULL,
  license_type TEXT NOT NULL, -- 'corporate_member', 'private_building', 'city_civic'
  licensee_id TEXT NOT NULL, -- human_id or city_id
  licensor_corporation_id TEXT NOT NULL,
  building_id TEXT REFERENCES buildings(id) ON DELETE SET NULL,
  city_id TEXT,
  is_permanent BOOLEAN NOT NULL DEFAULT FALSE,
  granted_game_day BIGINT NOT NULL,
  expiry_game_day BIGINT NOT NULL,
  royalty_per_day_crd NUMERIC(20,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active', -- 'active', 'renewal_window', 'expired'
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bld_patent_lic_licensee ON building_patent_licenses (licensee_id, status);
CREATE INDEX IF NOT EXISTS idx_bld_patent_lic_building ON building_patent_licenses (building_id);
CREATE INDEX IF NOT EXISTS idx_bld_patent_lic_city ON building_patent_licenses (city_id, status);

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS required_patent_id TEXT,
  ADD COLUMN IF NOT EXISTS patent_license_status TEXT DEFAULT 'unlicensed';

-- -----------------------------------------------------------------------------
-- Historical migration 053_harden_buildings_and_patents_canonical_schema.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 053: Canonical Building-Centric Ownership, Robust Patent Licensing Constraints, and Economic Unification

-- 1. Backfill and enforce canonical ownership_class on buildings
UPDATE buildings
SET ownership_class = CASE
  WHEN ownership_class IS NOT NULL AND ownership_class <> '' THEN ownership_class
  WHEN ownership_type = 'municipal' THEN 'civic'
  WHEN ownership_type = 'public' THEN 'public_investment'
  ELSE 'private'
END
WHERE ownership_class IS NULL OR ownership_class = '';

ALTER TABLE buildings
  ALTER COLUMN ownership_class SET NOT NULL,
  ALTER COLUMN ownership_class SET DEFAULT 'private',
  ALTER COLUMN ownership_type DROP NOT NULL,
  ALTER COLUMN max_staff_slots DROP NOT NULL,
  ALTER COLUMN base_revenue_crd DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_buildings_ownership_class'
  ) THEN
    ALTER TABLE buildings ADD CONSTRAINT chk_buildings_ownership_class
      CHECK (ownership_class IN ('private', 'civic', 'public_investment'));
  END IF;
END $$;

-- 2. Add validation constraints on building patent licenses safely
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_bld_patent_lic_type'
  ) THEN
    ALTER TABLE building_patent_licenses ADD CONSTRAINT chk_bld_patent_lic_type
      CHECK (license_type IN ('corporate_member', 'private_building', 'city_civic'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_bld_patent_lic_status'
  ) THEN
    ALTER TABLE building_patent_licenses ADD CONSTRAINT chk_bld_patent_lic_status
      CHECK (status IN ('active', 'renewal_window', 'expired'));
  END IF;
END $$;

-- 3. Prevent duplicate active licenses for the same building and patent
CREATE UNIQUE INDEX IF NOT EXISTS uq_building_patent_active
  ON building_patent_licenses (building_id, patent_id)
  WHERE status IN ('active', 'renewal_window') AND building_id IS NOT NULL;

-- 4. Prevent duplicate active city-wide civic licenses for the same city and patent
CREATE UNIQUE INDEX IF NOT EXISTS uq_city_patent_active
  ON building_patent_licenses (city_id, patent_id)
  WHERE status IN ('active', 'renewal_window') AND license_type = 'city_civic' AND city_id IS NOT NULL;

-- 5. Prevent duplicate civic dividend payouts for the same city and day
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_civic_dividend_city_day'
  ) THEN
    ALTER TABLE civic_dividend_payouts ADD CONSTRAINT uq_civic_dividend_city_day
      UNIQUE (city_id, day);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Historical migration 054_drop_legacy_building_columns.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 054: Building Construction Lifecycle & Legacy Column Purge

-- 1. Add construction timeline and progress columns
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS construction_started_game_day INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS construction_complete_game_day INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS construction_progress NUMERIC(5,2) DEFAULT 100.0;

-- 2. Backfill existing active buildings to 100% completed
UPDATE buildings
SET
  construction_progress = 100.0,
  construction_started_game_day = COALESCE(created_game_day, 1),
  construction_complete_game_day = COALESCE(created_game_day, 1)
WHERE status = 'active' AND (construction_progress IS NULL OR construction_progress = 0);

-- 3. Drop legacy columns that are no longer used by any application code
ALTER TABLE buildings
  DROP COLUMN IF EXISTS ownership_type,
  DROP COLUMN IF EXISTS max_staff_slots,
  DROP COLUMN IF EXISTS base_revenue_crd;

-- -----------------------------------------------------------------------------
-- Historical migration 055_harden_building_accounting_and_constraints.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 055: Building Accounting Model Hardening, Settlement Journals, and Referential Integrity

-- 1. Ensure zero-balance market clearing account exists
INSERT INTO account_balances (account_id, owner_id, currency, balance)
VALUES
  ('account-market-clearing', 'SYSTEM', 'CREDIT', 0.00)
ON CONFLICT (account_id) DO NOTHING;

-- 2. Ensure operations accounts exist for all existing cities
INSERT INTO account_balances (account_id, owner_id, currency, balance)
SELECT 'account-city-operations-' || id, id, 'CREDIT', 0.00
FROM cities
ON CONFLICT (account_id) DO NOTHING;

-- 3. Add strict check constraints on buildings construction fields
ALTER TABLE buildings
  DROP CONSTRAINT IF EXISTS chk_building_construction_progress,
  DROP CONSTRAINT IF EXISTS chk_building_construction_days;

ALTER TABLE buildings
  ADD CONSTRAINT chk_building_construction_progress CHECK (construction_progress >= 0.0 AND construction_progress <= 100.0),
  ADD CONSTRAINT chk_building_construction_days CHECK (construction_complete_game_day >= construction_started_game_day);

-- 4. Add referential integrity and type constraints on building_patent_licenses
ALTER TABLE building_patent_licenses
  DROP CONSTRAINT IF EXISTS fk_patent_license_patent,
  DROP CONSTRAINT IF EXISTS fk_patent_license_city,
  DROP CONSTRAINT IF EXISTS chk_patent_license_type,
  DROP CONSTRAINT IF EXISTS chk_patent_license_status;

ALTER TABLE building_patent_licenses
  ADD CONSTRAINT fk_patent_license_patent FOREIGN KEY (patent_id) REFERENCES patents(id) ON DELETE CASCADE,
  ADD CONSTRAINT fk_patent_license_city FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE SET NULL,
  ADD CONSTRAINT chk_patent_license_type CHECK (license_type IN ('corporate_member', 'private_building', 'city_civic')),
  ADD CONSTRAINT chk_patent_license_status CHECK (status IN ('active', 'renewal_window', 'expired'));

-- 5. Daily Building Settlement Journals table for exact accounting and dividend auditability
CREATE TABLE IF NOT EXISTS building_settlement_journals (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  city_id TEXT NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  day INTEGER NOT NULL,
  ownership_class TEXT NOT NULL,
  gross_revenue_crd NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (gross_revenue_crd >= 0),
  operating_costs_crd NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (operating_costs_crd >= 0),
  net_surplus_crd NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (net_surplus_crd >= 0),
  condition_start NUMERIC(5,2) NOT NULL,
  condition_end NUMERIC(5,2) NOT NULL,
  auto_repaired BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_building_settlement_journal_day UNIQUE (building_id, day)
);

CREATE INDEX IF NOT EXISTS idx_bld_settle_city_day ON building_settlement_journals (city_id, day);
CREATE INDEX IF NOT EXISTS idx_bld_settle_building_day ON building_settlement_journals (building_id, day);

-- -----------------------------------------------------------------------------
-- Historical migration 056_civic_rankings_table.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 056: Civic Rankings Table for Periodic Relative Data-Driven Rankings
CREATE TABLE IF NOT EXISTS civic_rankings (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    entity_name TEXT NOT NULL,
    rank INTEGER NOT NULL,
    rank_delta INTEGER NOT NULL DEFAULT 0,
    final_score INTEGER NOT NULL,
    metrics_line TEXT NOT NULL,
    sub_indexes JSONB NOT NULL DEFAULT '{}',
    raw_metrics JSONB NOT NULL DEFAULT '{}',
    affiliation TEXT,
    game_day INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_civic_rankings_entity UNIQUE (category, entity_id)
);

CREATE INDEX IF NOT EXISTS idx_civic_rankings_cat_score ON civic_rankings(category, final_score DESC, rank ASC);

-- -----------------------------------------------------------------------------
-- Historical migration 057_community_application_questions_and_reasons.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 057: Community application questions, applicant response messages, and rejection reasons.

ALTER TABLE communities
  ADD COLUMN IF NOT EXISTS application_question TEXT NOT NULL DEFAULT '';

ALTER TABLE community_membership_requests
  ADD COLUMN IF NOT EXISTS application_message TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT NOT NULL DEFAULT '';

-- -----------------------------------------------------------------------------
-- Historical migration 058_fix_community_unique_constraints.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Migration 058: Drop restrictive unique constraint on community_membership_requests so users can re-apply/re-join freely.
ALTER TABLE community_membership_requests
  DROP CONSTRAINT IF EXISTS community_membership_requests_community_id_human_id_status_key;

-- -----------------------------------------------------------------------------
-- Historical migration 059_rename_dynasties_to_houses.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- EARTH PostgreSQL Migration 056: Rename Dynasties to Houses across all lineage, perk, and heirloom tables

-- 1. Rename core tables if they exist
alter table if exists dynasties rename to houses;
alter table if exists dynasty_lineage_records rename to house_lineage_records;
alter table if exists dynasty_perks rename to house_perks;
alter table if exists dynasty_heirlooms rename to house_heirlooms;

-- 2. Rename columns in houses
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'houses' and column_name = 'dynasty_name'
  ) then
    alter table houses rename column dynasty_name to house_name;
  end if;
end $$;

-- 3. Rename columns in house_lineage_records
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'house_lineage_records' and column_name = 'dynasty_id'
  ) then
    alter table house_lineage_records rename column dynasty_id to house_id;
  end if;
end $$;

-- 4. Rename columns in house_perks
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'house_perks' and column_name = 'dynasty_id'
  ) then
    alter table house_perks rename column dynasty_id to house_id;
  end if;
end $$;

-- 5. Rename columns in house_heirlooms
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'house_heirlooms' and column_name = 'dynasty_id'
  ) then
    alter table house_heirlooms rename column dynasty_id to house_id;
  end if;
end $$;

-- 6. Rename columns in deceased_profiles & character_lineage
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'deceased_profiles' and column_name = 'dynasty_name'
  ) then
    alter table deceased_profiles rename column dynasty_name to house_name;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_name = 'character_lineage' and column_name = 'dynasty_name'
  ) then
    alter table character_lineage rename column dynasty_name to house_name;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_name = 'dispatch_messages' and column_name = 'sender_dynasty_name'
  ) then
    alter table dispatch_messages rename column sender_dynasty_name to sender_house_name;
  end if;
end $$;

-- 7. Update indices
create index if not exists idx_houses_email on houses(email);
create index if not exists idx_house_lineage_records_house on house_lineage_records(house_id, generation asc);
create index if not exists idx_house_lineage_records_human on house_lineage_records(human_id);
create index if not exists idx_house_perks_house on house_perks(house_id);
create index if not exists idx_house_heirlooms_house on house_heirlooms(house_id);
create index if not exists deceased_profiles_house_idx on deceased_profiles(house_name, final_legacy desc);

-- -----------------------------------------------------------------------------
-- Historical migration 060_constitutional_rule_registry.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS constitutional_rules (
  id text PRIMARY KEY,
  part_number integer NOT NULL,
  article_number integer NOT NULL DEFAULT 1,
  rule_number text NOT NULL UNIQUE,
  title text NOT NULL,
  description text NOT NULL,
  default_value text NOT NULL,
  permitted_values text,
  active boolean NOT NULL DEFAULT true,
  updated_game_day bigint,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS constitutional_rules_active_order_idx
  ON constitutional_rules (active, part_number, article_number, rule_number);

INSERT INTO constitutional_rules (id, part_number, article_number, rule_number, title, description, default_value, permitted_values)
VALUES
  ('CONST-1-1', 1, 1, '1.1', 'Rule Precedence', 'A city override replaces a corporation override; a corporation override replaces the Earth baseline.', 'Earth baseline', 'Earth, Corporation, or City source'),
  ('CONST-1-2', 1, 1, '1.2', 'Override Authority', 'A rule may be changed only by the institutional levels explicitly permitted for that rule.', 'Rule-specific authority', 'Only the levels named by that rule'),
  ('CONST-2-1', 2, 1, '2.1', 'Income Tax Rate', 'The Earth levy is the fallback. A permitted city or corporation charter rate replaces it.', 'Earth income levy', '0–50%'),
  ('CONST-2-2', 2, 1, '2.2', 'Sales Tax Rate', 'Applies through the City → Corporation → Earth resolution order.', 'Earth sales levy', '0–25%'),
  ('CONST-2-3', 2, 1, '2.3', 'Corporate Tax Rate', 'The active local charter rate is used when present; otherwise the Earth business levy applies.', 'Earth business levy', '0–50%'),
  ('CONST-2-4', 2, 1, '2.4', 'Property Tax Rate', 'Defined for institutional charters; its economic settlement is reserved for the property-tax system.', 'Earth property baseline', '0–30%'),
  ('CONST-3-1', 3, 1, '3.1', 'Proposal Eligibility', 'An active, politically eligible resident or corporation member may propose and vote in that institution.', 'Active, politically eligible member or resident', NULL),
  ('CONST-3-2', 3, 1, '3.2', 'Quorum & Approval', 'Active governance-rule versions supply the quorum and approval values for a proposal.', '25% quorum · 50% approval', 'Active governance-rule version'),
  ('CONST-3-3', 3, 1, '3.3', 'Cooling-Off & Appeal', 'Passed proposals wait before execution and may be constitutionally challenged.', '1 game-day implementation delay', NULL),
  ('CONST-4-1', 4, 1, '4.1', 'Corporation Admission Policy', 'A corporation selects open entry or approval-based membership for its own institution.', 'Open admission', 'Open or approval')
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 061_restore_constitutional_statutes.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
DELETE FROM constitutional_rules;

INSERT INTO constitutional_rules (id, part_number, article_number, rule_number, title, description, default_value, permitted_values)
VALUES
  ('RULE-1-1', 1, 1, '1.1', 'Basic Income Levy', 'Earth applies the default levy to eligible citizens; a permitted institution charter may replace the rate.', 'Active Earth tax-rule rate', '0–50%'),
  ('RULE-1-2', 1, 1, '1.2', 'Business Tax Rate', 'Earth applies the default rate to taxable business revenue; a permitted institution charter may replace the rate.', 'Active Earth tax-rule rate', '0–50%'),
  ('RULE-1-3', 1, 1, '1.3', 'Market Sales Tax Rate', 'Earth supplies the market rate; a permitted institutional charter may replace the rate for an affiliated user.', 'Active Earth market tax-rule rate', '0–25%'),
  ('RULE-2-1', 2, 1, '2.1', 'Quorum', 'A proposal must reach the active governance-rule participation threshold to be valid.', '25%', 'Active governance-rule value'),
  ('RULE-2-2', 2, 1, '2.2', 'Approval Threshold', 'A valid proposal must reach the active governance-rule approval threshold to pass.', '50%', 'Active governance-rule value'),
  ('RULE-2-3', 2, 1, '2.3', 'Implementation Delay', 'A passed proposal waits before it may be executed.', '1 game day', NULL),
  ('RULE-3-1', 3, 1, '3.1', 'Corporation Admission Policy', 'A corporation decides whether eligible applicants join immediately or require approval.', 'Open', 'Open or approval');

-- -----------------------------------------------------------------------------
-- Historical migration 062_seed_earth_constitution_values.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- The active Earth tax rules are the authoritative live values for the
-- Constitution's Revenue rules.  Existing live values are never overwritten.
INSERT INTO tax_rules (id, scope, category, rate, active, version)
VALUES
  ('TAX-OUC-BASIC', 'global', 'basic_income', 0.020000, true, 1),
  ('TAX-OUC-BUSINESS', 'global', 'business', 0.050000, true, 1),
  ('TAX-OUC-MARKET', 'global', 'market', 0.010000, true, 1)
ON CONFLICT (id) DO NOTHING;

-- Implementation delay belongs to the active governance rule, alongside its
-- quorum and approval threshold. Existing rules receive the persisted value.
ALTER TABLE governance_rules
  ADD COLUMN IF NOT EXISTS implementation_delay_days integer NOT NULL DEFAULT 1
  CHECK (implementation_delay_days >= 0 AND implementation_delay_days <= 30);

-- -----------------------------------------------------------------------------
-- Historical migration 063_earth_governance_baseline_and_rule_authority.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
ALTER TABLE constitutional_rules
  ADD COLUMN IF NOT EXISTS authority text NOT NULL DEFAULT 'Earth';

UPDATE constitutional_rules
SET authority = CASE WHEN rule_number = '3.1' THEN 'Corporation' ELSE 'Earth' END;

-- The baseline is a real active Earth governance record. It is inserted only
-- when the world has no active OUC governance rule, and may later be replaced
-- through the normal governance process.
INSERT INTO governance_rules (
  id, institution_id, name, category, quorum_threshold, approval_threshold,
  voting_period_days, implementation_delay_days, version, status, created_by
)
SELECT
  'GOV-OUC-BASELINE-v1', institutions.id, 'Earth governance baseline',
  'governance', 0.25, 0.50, 30, 1, 1, 'active', human.id
FROM institutions
CROSS JOIN LATERAL (SELECT id FROM humans ORDER BY id LIMIT 1) human
WHERE institutions.kind = 'OUC'
  AND NOT EXISTS (
    SELECT 1
    FROM governance_rules
    WHERE governance_rules.institution_id = institutions.id
      AND governance_rules.status = 'active'
  )
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 064_membership_admission_rules.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
INSERT INTO constitutional_rules (
  id, part_number, article_number, rule_number, title, description,
  default_value, permitted_values, authority, active
)
VALUES
  (
    'RULE-3-2', 3, 1, '3.2', 'City Admission Policy',
    'A city follows the admission policy of its parent corporation. A city cannot override that policy.',
    'Parent corporation policy', NULL, 'Corporation', true
  ),
  (
    'RULE-3-3', 3, 1, '3.3', 'Community Admission Policy',
    'A community chooses whether eligible citizens join immediately or require approval.',
    'Open', 'Open or approval', 'Community', true
  )
ON CONFLICT (id) DO UPDATE SET
  part_number = EXCLUDED.part_number,
  article_number = EXCLUDED.article_number,
  rule_number = EXCLUDED.rule_number,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  default_value = EXCLUDED.default_value,
  permitted_values = EXCLUDED.permitted_values,
  authority = EXCLUDED.authority,
  active = true,
  updated_at = now();

-- -----------------------------------------------------------------------------
-- Historical migration 065_constitutional_succession_rules.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
INSERT INTO constitutional_rules (
  id, part_number, article_number, rule_number, title, description,
  default_value, permitted_values, authority, active
)
VALUES
  (
    'RULE-4-1', 4, 1, '4.1', 'Primary Heir Allocation',
    'The designated primary heir receives liquid estate credits and all transferable productive assets.',
    '70%', NULL, 'Earth', true
  ),
  (
    'RULE-4-2', 4, 1, '4.2', 'Municipal Trust Allocation',
    'The deceased citizen’s resident city receives a statutory allocation for public services.',
    '20%', NULL, 'Earth', true
  ),
  (
    'RULE-4-3', 4, 1, '4.3', 'House Reserve Allocation',
    'A statutory allocation is reserved for the citizen’s House and its generational continuity.',
    '10%', NULL, 'Earth', true
  ),
  (
    'RULE-4-4', 4, 1, '4.4', 'Estate Buffer',
    'An unclaimed estate remains protected before public liquidation.',
    '30 game days', NULL, 'Earth', true
  )
ON CONFLICT (id) DO UPDATE SET
  part_number = EXCLUDED.part_number,
  article_number = EXCLUDED.article_number,
  rule_number = EXCLUDED.rule_number,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  default_value = EXCLUDED.default_value,
  permitted_values = EXCLUDED.permitted_values,
  authority = EXCLUDED.authority,
  active = true,
  updated_at = now();

-- -----------------------------------------------------------------------------
-- Historical migration 066_constitutional_public_order_rules.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
INSERT INTO constitutional_rules (
  id, part_number, article_number, rule_number, title, description,
  default_value, permitted_values, authority, active
)
VALUES
  (
    'RULE-1-4', 1, 1, '1.4', 'Business-Tax Allocation',
    'Business-tax revenue is allocated between the resident city, parent corporation, and Earth treasury.',
    'City 60% · Corporation 25% · Earth 15%', NULL, 'Earth', true
  ),
  (
    'RULE-2-4', 2, 1, '2.4', 'Political Eligibility',
    'Only an active citizen who has reached their recorded political-maturity day may hold civic office.',
    'Active citizen after political maturity', NULL, 'Earth', true
  ),
  (
    'RULE-3-4', 3, 1, '3.4', 'City–Corporation Affiliation',
    'A city belongs to a parent corporation, and residency must remain compatible with that corporation membership.',
    'Parent corporation affiliation required', NULL, 'Earth', true
  ),
  (
    'RULE-4-5', 4, 1, '4.5', 'Estate Liquidation',
    'An unclaimed estate is liquidated after the statutory estate buffer expires.',
    'After 30 game days', NULL, 'Earth', true
  )
ON CONFLICT (id) DO UPDATE SET
  part_number = EXCLUDED.part_number,
  article_number = EXCLUDED.article_number,
  rule_number = EXCLUDED.rule_number,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  default_value = EXCLUDED.default_value,
  permitted_values = EXCLUDED.permitted_values,
  authority = EXCLUDED.authority,
  active = true,
  updated_at = now();

-- -----------------------------------------------------------------------------
-- Historical migration 067_business_tax_allocation_values.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS business_tax_allocation_rules (
  id text PRIMARY KEY,
  city_share numeric(10,6) NOT NULL CHECK (city_share >= 0 AND city_share <= 1),
  corporation_share numeric(10,6) NOT NULL CHECK (corporation_share >= 0 AND corporation_share <= 1),
  earth_share numeric(10,6) NOT NULL CHECK (earth_share >= 0 AND earth_share <= 1),
  active boolean NOT NULL DEFAULT true,
  version integer NOT NULL DEFAULT 1,
  CHECK (city_share + corporation_share + earth_share = 1)
);

INSERT INTO business_tax_allocation_rules (id, city_share, corporation_share, earth_share, active, version)
VALUES ('BUSINESS-TAX-ALLOCATION-EARTH', 0.60, 0.25, 0.15, true, 1)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Historical migration 068_remove_social_initiatives.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Remove the retired social-initiatives feature and all of its operational data.
-- Research projects, civic megaprojects, contracts, and non-social notifications remain intact.

DELETE FROM notifications
WHERE notification_type = 'social'
   OR id LIKE 'SOCIAL-%'
   OR entity_id LIKE 'social-%';

DELETE FROM world_events
WHERE event_type LIKE 'social.%'
   OR (event_type = 'institution.project_completed' AND details LIKE '%initiativeId%');

DELETE FROM ledger_entries
WHERE reason_type IN ('social_escrow_lock', 'social_escrow_release', 'social_escrow_forfeit')
   OR reason_id LIKE 'social-%'
   OR debit_account LIKE 'social-social-%'
   OR credit_account LIKE 'social-social-%';

DELETE FROM account_balances
WHERE account_id LIKE 'social-social-%'
   OR owner_id LIKE 'social-social-%';

DROP TABLE IF EXISTS social_initiative_members;
DROP TABLE IF EXISTS social_initiatives;
DROP TABLE IF EXISTS social_relationships;

-- -----------------------------------------------------------------------------
-- Historical migration 069_remove_machine_system.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Retire the machine economy. Buildings are now the sole productive assets.

DELETE FROM ownership_events WHERE asset_type = 'MACHINE' OR reason_type IN ('machine_acquisition', 'machine_upgrade', 'machine_sale', 'machine_liquidation', 'recycling');
DELETE FROM ledger_entries WHERE reason_type IN ('machine_acquisition', 'machine_upgrade', 'machine_sale', 'machine_liquidation', 'business_depreciation');
DELETE FROM notifications WHERE entity_id LIKE 'M-%' OR body ILIKE '%machine%';

DROP TABLE IF EXISTS municipal_labor_pool;
-- The building_staff_assignments table is not present in the current schema. These statements are removed.
-- DELETE FROM building_staff_assignments WHERE machine_id IS NOT NULL;
-- ALTER TABLE building_staff_assignments DROP CONSTRAINT IF EXISTS uq_building_machine_slot;
-- ALTER TABLE building_staff_assignments DROP CONSTRAINT IF EXISTS building_staff_assignments_staff_type_check;
-- ALTER TABLE building_staff_assignments DROP COLUMN IF EXISTS machine_id;
-- ALTER TABLE building_staff_assignments DROP COLUMN IF EXISTS staff_type;

DROP TABLE IF EXISTS business_assets;
DROP TABLE IF EXISTS maintenance_events;
DROP TABLE IF EXISTS production_events;
DROP TABLE IF EXISTS recycling_events;
DROP TABLE IF EXISTS machine_upgrade_events;
DROP TABLE IF EXISTS machine_sales;
DROP TABLE IF EXISTS machine_acquisitions;
DROP TABLE IF EXISTS machines;

-- -----------------------------------------------------------------------------
-- Historical migration 070_remove_patent_system.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Retire patents and licensing. Research remains, and completed research is
-- adopted directly by businesses and buildings.

DELETE FROM ledger_entries
WHERE reason_type IN (
  'patent_grant', 'patent_license_purchase', 'patent_license_renewal',
  'technology_license_fee', 'technology_royalty'
);

DELETE FROM notifications
WHERE notification_type IN ('patent', 'patent_license')
   OR title ILIKE '%patent%'
   OR body ILIKE '%patent%';

DROP TABLE IF EXISTS building_patent_licenses;
DROP TABLE IF EXISTS technology_licenses;
DROP TABLE IF EXISTS corporation_technology_shares;
DROP TABLE IF EXISTS patents;

ALTER TABLE buildings DROP COLUMN IF EXISTS required_patent_id;
ALTER TABLE buildings DROP COLUMN IF EXISTS patent_license_status;

DROP INDEX IF EXISTS idx_bld_patent_lic_licensee;
DROP INDEX IF EXISTS idx_bld_patent_lic_building;
DROP INDEX IF EXISTS idx_bld_patent_lic_city;
DROP INDEX IF EXISTS uq_building_patent_active;
DROP INDEX IF EXISTS uq_city_patent_active;

-- -----------------------------------------------------------------------------
-- Historical migration 071_ai_recommendation_feedback.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
CREATE TABLE ai_recommendation_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  human_id TEXT NOT NULL REFERENCES humans(id),
  recommendation_type TEXT NOT NULL CHECK (recommendation_type IN ('decision_queue','objective','briefing')),
  recommendation_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('approved','dismissed','deferred','viewed')),
  context_snapshot JSONB,
  game_day INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_rec_feedback_human ON ai_recommendation_feedback(human_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- Historical migration 072_scheduler_tick_log.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
CREATE TABLE scheduler_tick_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_day INTEGER NOT NULL,
  engine TEXT NOT NULL,
  rows_processed INTEGER DEFAULT 0,
  duration_ms INTEGER,
  status TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok','error','skipped')),
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_scheduler_tick_logs_day ON scheduler_tick_logs(game_day DESC, engine);

-- -----------------------------------------------------------------------------
-- Historical migration 073_personal_life_maintenance.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
-- Daily, universal life maintenance.  Each row is a durable explanation of
-- what a resident was charged (or could not yet pay) on a game day.
create table if not exists personal_life_maintenance (
  human_id text not null references humans(id),
  game_day bigint not null,
  food numeric(20,2) not null,
  housing numeric(20,2) not null,
  energy numeric(20,2) not null,
  health numeric(20,2) not null,
  connectivity numeric(20,2) not null,
  total numeric(20,2) not null,
  paid numeric(20,2) not null default 0,
  unpaid numeric(20,2) not null default 0,
  city_id text references cities(id),
  status text not null check (status in ('settled', 'partially_settled', 'deferred')),
  created_at timestamptz not null default now(),
  primary key (human_id, game_day)
);

create index if not exists personal_life_maintenance_human_day_idx
  on personal_life_maintenance(human_id, game_day desc);

-- -----------------------------------------------------------------------------
-- Historical migration 074_resource_first_life_maintenance.sql consolidated into this bootstrap baseline.
-- -----------------------------------------------------------------------------
alter table personal_life_maintenance
  add column if not exists food_used numeric(20,2) not null default 0,
  add column if not exists energy_used numeric(20,2) not null default 0,
  add column if not exists compute_used numeric(20,2) not null default 0,
  add column if not exists credits_for_resources numeric(20,2) not null default 0,
  add column if not exists life_condition_before integer not null default 100,
  add column if not exists life_condition_after integer not null default 100,
  add column if not exists shortfall_notes text not null default '';

create table if not exists human_life_conditions (
  human_id text primary key references humans(id),
  score integer not null default 100 check (score between 0 and 100),
  updated_game_day bigint not null default 0,
  last_reason text not null default ''
);

-- Mark the consolidated history as applied so the normal migration runner begins at 075.
-- These checksums are intentionally exact and are verified by db:verify:initial.
INSERT INTO earth_schema_migrations (version, name, checksum) VALUES
  (1, '001_initial.sql', 'ab2c3c5425898a5c9041c7c84d722206cace17b5a6145fbdbf9b46279ec1c1ed'),
  (2, '002_earth_feature_schema.sql', 'd3e23fa76fa41b4d8f3168e650e195fdbee68ffd103a43ec6b277a8ad714f7da'),
  (3, '003_import_compatibility.sql', '8f919b9f02354614d4253143f358a208c0de4958481d96a61cc56b002fd30eef'),
  (4, '004_correlation_key_compatibility.sql', '4c0830c75f4d92e2f144e845fe7212bd8657e7ebfbca9bd7cfbb65a7945b86e0'),
  (5, '005_institution_dissolution.sql', '6bfcd6610fbb6e23fd182732efd1cff8a3ac7870af408d6241657d27bc8e8cd2'),
  (6, '006_event_outbox.sql', '68e4f2850ee6187b8d824f288e35af45eb3a0e49eb984b786d66dcabc3a87335'),
  (7, '007_game_time_governance_windows.sql', '264240bb830927c6fad388f34a6c3d538ac3cae9eca03908ff0211f7ec1123da'),
  (8, '008_atomic_credit_transfer.sql', '9d8784bd52d00586a03b2e4de2f8b8b6098a47af718171cd8e7b73bbbe19d26d'),
  (9, '009_market_order_escrow.sql', 'ef8bcfe328385ba8cf025d282eb46438bcb6cb5c222fc424c5b2ce204197038f'),
  (10, '010_market_order_escrow_zero_reservations.sql', '0805e3db0106d789c9ef6e0b7cd80e2fb88042a485b684f9938295097d5f1bfd'),
  (11, '011_institution_credit_accounts.sql', 'f22614497f230c3cdad37ffc122eb669efa8e83f2b63f55f2a0f0c73bfc81b9f'),
  (12, '012_registry_credit_accounts.sql', '44c570fed789532a74120ff2a3d93daf21aba4a2c9b3ef1f1cddedc29e7247b8'),
  (13, '013_city_budget_accounts.sql', '200a9102890f44f45153bdb9a68d8c457e43500785da167db41ee43f6d8ccee2'),
  (14, '014_recycling_idempotency.sql', 'f0e5b68d84996e39c53367ad7029d38472dfbddfe81f827f9ebd221436d4b704'),
  (15, '015_business_liquidation_idempotency.sql', 'c42373738911558157245602f788439f029091279be1545f317b901c02f01568'),
  (16, '016_scheduler_readiness_heartbeat.sql', '76863e992f43daba647a325895d5a0dfa114ce8b72d2f090bdea57518a9e26d7'),
  (17, '017_initialize_scheduler_heartbeat.sql', '6e7d83107676d08949da5c5c2cf30ed369960b2c4530a45e5ce766af98672547'),
  (18, '018_normalize_json_structures.sql', '45a6125638c4cd29b95ad01eb5da5e64515d6bf18c63f1f27e4cf71c3f06a0a7'),
  (19, '019_drop_obsolete_json_columns.sql', '0f1c14cabf459c70389ca948ce1593abd4bf58e64792d3b77fdcc772367271ad'),
  (20, '020_migrate_to_nano_markup_text.sql', '3c90601a2eb5db6f2169b8093bf85aee8c778a2a13ff7da91845ee1b0776d04f'),
  (21, '021_migrate_world_events_to_nano_markup.sql', '82bb50b8e29b7cce27242401c87d8fe3bfe7d2e96d76f9ee930b76d10c3bbc62'),
  (22, '022_effective_genesis_and_simulation_offset.sql', '62f97c84eee6ae9e054cfc49e062f4486ff484bbf8ca2afc2411b94a2ccd7ea3'),
  (23, '023_pantheon_cemetery_and_rebirth.sql', '574bb78f1b5abf4b82b48e4204971da637a2965a1e18de2ce72bb8b5270fd656'),
  (24, '024_communications_and_dispatch.sql', '912100dbab644a8d6ad328e43c8f7068c211163641b32766e801c2f6924b98d6'),
  (25, '025_allow_food_resource_balance.sql', '33040ddd10e9b3c8c246c7213dfd7b35827a918002e8d41c5e23b9ccd99bc338'),
  (26, '026_automated_supply_contracts_and_escrow.sql', '31dce0d969554b87781f965cd0a88a8241e0812ee79efd53cef12d471a8108c2'),
  (27, '027_planetary_map_and_territory_concessions.sql', 'b8671da6c98a9b912d758f31df85bc5e4110f409a61bf30fea7e964d1106e7ab'),
  (28, '028_dynasty_lineage_and_heirlooms.sql', '652e342de6f127c31441effb7d4adc8e8d2b5cbce6a62d3f552b5400fb0a0980'),
  (29, '029_commodity_futures_and_candlestick_history.sql', '8d69767f40cebc98f49cb479f88f5e7106b678992b46667b3e6cba9e32e90cfb'),
  (30, '030_net_worth_snapshots_and_asset_history.sql', 'f853859f2f6eb5fef4df8ebafcaf65723d832a5c02323f831cd0ea4058bd7710'),
  (31, '031_auth_email_delivery_observability.sql', '533692edaeb59901e248fb317287dfcea238dec9e2f1f77a5a6385defc512224'),
  (32, '032_social_gameplay.sql', '221cdb1b7af7d97e26f861bffeabaae95f1168853d6380aa12e2808eeeb7297b'),
  (33, '033_social_relationships_timeline.sql', 'dab453f726a3d8737e212779361a050176e2d69a4377ffdb73ecd7a0c6b56f2a'),
  (34, '034_remove_planetary_map.sql', 'e3c5a2a72f282d04a8e9b8319ce09e413ee5d6b718c4034dfaf82a9b9787a08a'),
  (35, '035_ensure_components_market.sql', '9fd8b19cf237a1a0a3e35ecae0a13d164c2bf6c33afb147d8e944d9ef7461c09'),
  (36, '036_components_market_history.sql', 'a25737645a276ed333d4192394d84b91624fa699a71da045866e4f292af8adf2'),
  (37, '037_continuous_engine_schema.sql', '84772fa57978ca8a679bc0f2946c89370586fe8a7fed16a53c3ba5b63820ea77'),
  (38, '038_seed_canonical_institutions.sql', '4f1d96b92d06cc43adcf5a71f0be186ba58a8f407eb8c634395ffb2fd6651425'),
  (39, '039_seed_market_catalog.sql', 'fdc1a262f85edf160c72ed6ee3a88dc91d9d1747216862040605e473ff83e288'),
  (40, '040_enable_food_market.sql', '9e18b34e7ba1f74eeec1c93145841cc05752e3fde8754d90c12bbd63d944b5d4'),
  (41, '041_business_workforce.sql', '4f88de02cd3d6fbf45c4179857d002ab4b61826f18c8be87deefddb00380a923'),
  (42, '042_link_cities_to_corporations.sql', 'd807c00613c8dd457ed49b4cd351e50ae2f705ed7c7567c89de169f31754683d'),
  (43, '043_corporation_shared_technology.sql', '28bbb42a98dee5de116284469d1837dd391ac9e9cd03018c6f0039f6aa13c977'),
  (44, '044_enable_food_production_events.sql', '6dc518b4d96469e69c193aec0b00fcaf8a4a3f747c4600e9d5d39f4f63f1e281'),
  (45, '045_business_attribution_for_technology_licenses.sql', '4a0a93d85db8209d42fa397290aca394871e41e55cdebf71c3c711a3bf99fbb2'),
  (46, '046_business_technology_adoption.sql', '9a4221299e462dddd7091e90438b9e36a36f8de7258a58a54b33af96e4d29a7f'),
  (47, '047_institution_charter_rules.sql', '21ddf5dde065a138a288636266f7d5bc6269f726ff008d2e55842fdb4c9926e5'),
  (48, '048_corporation_membership_policy.sql', '0fe68fc5f9b181b3f1416e059d6e68dad3b2fe83570e31bb05054b563bef3749'),
  (49, '049_community_management_and_roles.sql', 'cc362ca8569dcd66f5e822660ccb5ab0d3a3d3113585e4390f1db7fa7bc8b8e2'),
  (50, '050_real_estate_and_municipal_labor.sql', '38ad72d07ff72d209ec279b149108e13a511b78e45ea2904f972f2ebc84e439b'),
  (51, '051_building_centric_urban_economy.sql', '335bacc8c0b4afa614a6df4f342de10c233f2ae09337b97755372a51a3306c73'),
  (52, '052_patents_buildings_licensing_integration.sql', '50ca6dbed9e471aa60763a388c371874051a7dd165cbbd27e33772cd93834ef8'),
  (53, '053_harden_buildings_and_patents_canonical_schema.sql', 'bd2f244bb503c78aa4c8a70a8ffcb4ce0eba7b4dc82f9ad335cd86a7f92892ce'),
  (54, '054_drop_legacy_building_columns.sql', '953b4c810c826f4750e8aad36b4a756f598127c1932483dc7ba285b9dff6c7b5'),
  (55, '055_harden_building_accounting_and_constraints.sql', '75524f13c4d55f330bd5e329501bd322031c461b18861fea4da52b4f5e822a63'),
  (56, '056_civic_rankings_table.sql', 'bb6981c304a8e046d019780b656a40ec5bd9c565cf0b189655c93e2eb270ca91'),
  (57, '057_community_application_questions_and_reasons.sql', 'a648b5ae8bcb649fa10cc693044f996afe9071d7fe0023e6cf2eb4ee041f1c99'),
  (58, '058_fix_community_unique_constraints.sql', 'fad80a7516354b3550d7034cd944298fccfce18eb59f52238386b6ae1b578361'),
  (59, '059_rename_dynasties_to_houses.sql', 'b939cf0d8a851fc7c8cbbc31dcc71471afd57cf27ed0b3dc56880ca6d946cc16'),
  (60, '060_constitutional_rule_registry.sql', '0ffb64be0ac576e7eb43c996b20f255035942f45a9414ca52192b2e3a231e518'),
  (61, '061_restore_constitutional_statutes.sql', '4bccc3f89daad5cd38a52ecb1b0ff68c4d79dd5d15cafdf15ca51d2d4590d7ed'),
  (62, '062_seed_earth_constitution_values.sql', '42d3026a6cade5cb45244b391bdc98762c564e9ff1bdc54e8bd77fcd00251975'),
  (63, '063_earth_governance_baseline_and_rule_authority.sql', '5f6c52ff7389887253c76d9e7242d632aa7f058c3ebd83b1a98f3156890e23d3'),
  (64, '064_membership_admission_rules.sql', '281ab88c31626e0d6b35ea838510951c11dab8c670a36ba6ffd39d402ba630fd'),
  (65, '065_constitutional_succession_rules.sql', '2bd9e3d73c3df2c3e3aa08318005387d879f93255e5f2e9f8363d14fd21a68b9'),
  (66, '066_constitutional_public_order_rules.sql', '6b86aae8e00ab3d42149fc0085a75e053968470e9fe756ba777be41dd7cf7965'),
  (67, '067_business_tax_allocation_values.sql', '523e24dba2309e1056bca26e4c919410d00738a018eba7a9fe13198d99ac6d1d'),
  (68, '068_remove_social_initiatives.sql', 'ed575f74e7ee12811254cfcc278c117a08fe9b564df5510bef068ee2b73ec052'),
  (69, '069_remove_machine_system.sql', '432a7c27744095dc8f17d643cf0004476e2ea70b68397a9d17d725d9ef59085b'),
  (70, '070_remove_patent_system.sql', 'c69bc5be8271738514fb938537b3e0175a1f7fbda2a1b4f240e6880d009a1d8d'),
  (71, '071_ai_recommendation_feedback.sql', '15424c39b8d99f77f88befd9f2827460d59a636c0508005dc227a4b25c17a87a'),
  (72, '072_scheduler_tick_log.sql', 'f20bae354b4d2644b12d69f32f5c97b2e33175ca3c86a7d06125af45eb721894'),
  (73, '073_personal_life_maintenance.sql', '96ca7424a5f44bbe707a984a37bf52772414695edc829aab70dae65237013b91'),
  (74, '074_resource_first_life_maintenance.sql', '97a23cd0f476bbba8672a339dab45fd6b8b52b68e3bf29d9dd509d6d7b4db70b');
