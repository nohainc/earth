-- EARTH PostgreSQL Migration 025: Allow food in resource_balances check constraint
alter table resource_balances drop constraint if exists resource_balances_resource_check;
alter table resource_balances add constraint resource_balances_resource_check check (resource in ('food','material','components','energy','compute'));
