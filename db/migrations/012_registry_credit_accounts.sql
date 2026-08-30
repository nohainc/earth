-- Explicit system accounts for credits committed to research and machine
-- registries. These balances preserve the money trail for asset funding.
insert into account_balances (account_id, owner_id, balance, currency)
values
  ('account-research-registry', 'SYSTEM-RESEARCH', 0, 'CREDIT'),
  ('account-machine-registry', 'SYSTEM-MACHINES', 0, 'CREDIT')
on conflict (account_id) do nothing;
