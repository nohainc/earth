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
