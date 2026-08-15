-- Compatibility structures discovered during the non-destructive D1 export review.
-- Kept separate so migration 002 remains checksum-stable after application.
create table if not exists resource_balances (
  owner_id text not null,
  resource text not null check (resource in ('material','components','energy','compute')),
  amount numeric(20,6) not null default 0 check (amount >= 0),
  primary key (owner_id, resource)
);
alter table research_projects add column if not exists focus text not null default 'efficiency' check (focus in ('efficiency','durability','safety','cost'));
