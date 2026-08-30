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
