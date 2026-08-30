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
