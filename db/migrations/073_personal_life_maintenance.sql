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
