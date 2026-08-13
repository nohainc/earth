insert into humans (id, account_id, display_name, age_years, standing, legacy)
values ('H-0044', 'account-amara', 'Amara Kline', 31, 742, 31)
on conflict (id) do nothing;

insert into institutions (id, kind, name) values
  ('OUC-001', 'OUC', 'Organization of United Corporations'),
  ('CORP-001', 'CORPORATION', 'Helios Cooperative'),
  ('CITY-0084', 'CITY', 'New Carthage'),
  ('BUS-1048', 'BUSINESS', 'Kline Works')
on conflict (id) do nothing;

insert into technologies (id, name, owner_id, progress)
values ('TECH-001', 'Adaptive Maintenance AI', 'H-0044', 72)
on conflict (id) do nothing;

insert into world_state (id, game_day, game_minute, health, market_batch_seconds)
values ('WORLD', 184, 462, 68, 498)
on conflict (id) do nothing;

insert into businesses (id, owner_id, name, policy, condition)
values ('B-1048', 'H-0044', 'Kline Works', 'reliability', 96)
on conflict (id) do nothing;

insert into resource_balances (owner_id, resource, amount) values
  ('H-0044', 'material', 420), ('H-0044', 'components', 86),
  ('H-0044', 'energy', 92), ('H-0044', 'compute', 64)
on conflict (owner_id, resource) do nothing;
