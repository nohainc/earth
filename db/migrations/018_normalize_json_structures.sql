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
