-- Give every open buy order an explicit CREDIT escrow account.
-- New orders fund this account through earth_transfer_credits; this backfill
-- preserves reservations made before escrow became explicit.
insert into account_balances (account_id, owner_id, balance, currency)
select
  'market-order-' || id,
  'market-order-' || id,
  coalesce(reserved_credits, 0),
  'CREDIT'
from market_orders
where side = 'buy'
  and status in ('open', 'partial')
  and coalesce(reserved_credits, 0) > 0
on conflict (account_id) do nothing;
