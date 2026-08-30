-- Preserve an explicit escrow row even for legacy zero-reservation orders.
-- The application excludes these invalid orders from settlement and allows
-- their owner to cancel them without creating a zero-value ledger entry.
insert into account_balances (account_id, owner_id, balance, currency)
select
  'market-order-' || id,
  'market-order-' || id,
  0,
  'CREDIT'
from market_orders
where side = 'buy'
  and status in ('open', 'partial')
on conflict (account_id) do nothing;
