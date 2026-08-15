-- Earmarked city budgets hold credits separately from the city's available
-- treasury. Existing BUDGET-* rows are backfilled before the new command path.
insert into account_balances (account_id, owner_id, balance, currency)
select 'account-budget-' || id, id, amount, 'CREDIT'
from budgets
where id like 'BUDGET-%'
on conflict (account_id) do nothing;
