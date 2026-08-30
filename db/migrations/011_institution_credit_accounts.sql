-- Represent institution-held credits as first-class PostgreSQL credit accounts.
-- The scalar treasury columns remain synchronized read projections for the
-- current API, while all future money movement uses these accounts.
insert into account_balances (account_id, owner_id, balance, currency)
select 'account-community-' || id, id, shared_credits, 'CREDIT'
from communities
on conflict (account_id) do nothing;

insert into account_balances (account_id, owner_id, balance, currency)
select 'account-city-' || id, id, treasury, 'CREDIT'
from cities
on conflict (account_id) do nothing;

insert into account_balances (account_id, owner_id, balance, currency)
select 'account-corporation-' || id, id, treasury, 'CREDIT'
from corporations
on conflict (account_id) do nothing;
