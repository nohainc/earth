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
