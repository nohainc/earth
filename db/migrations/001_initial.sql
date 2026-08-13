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
