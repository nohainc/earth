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
