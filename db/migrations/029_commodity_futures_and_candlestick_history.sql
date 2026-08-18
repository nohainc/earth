-- EARTH PostgreSQL Migration 029: Commodity Futures, Financial Derivatives & OHLC Candlestick Snapshots
-- Supports forward hedging contracts, locked collateral escrow, and historical market OHLC price charts.

create table if not exists commodity_futures_contracts (
  id text primary key,
  seller_human_id text not null references humans(id),
  buyer_human_id text references humans(id),
  commodity text not null check (commodity in ('energy', 'material', 'compute', 'food')),
  contract_size numeric(20,2) not null check (contract_size > 0),
  strike_price numeric(20,2) not null check (strike_price > 0),
  expiry_game_day bigint not null check (expiry_game_day > 0),
  collateral_locked numeric(20,2) not null default 0,
  premium_paid numeric(20,2) not null default 0,
  status text not null default 'open' check (status in ('open', 'matched', 'settled', 'defaulted', 'cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists market_ohlc_snapshots (
  id text primary key,
  commodity text not null check (commodity in ('energy', 'material', 'compute', 'food')),
  game_day bigint not null check (game_day > 0),
  open_price numeric(20,2) not null,
  high_price numeric(20,2) not null,
  low_price numeric(20,2) not null,
  close_price numeric(20,2) not null,
  volume numeric(20,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint uq_market_ohlc unique (commodity, game_day)
);

create index if not exists idx_commodity_futures_status on commodity_futures_contracts(commodity, status, expiry_game_day asc);
create index if not exists idx_commodity_futures_seller on commodity_futures_contracts(seller_human_id);
create index if not exists idx_commodity_futures_buyer on commodity_futures_contracts(buyer_human_id);
create index if not exists idx_market_ohlc_commodity_day on market_ohlc_snapshots(commodity, game_day desc);

-- Seed historical 30-day OHLC series for all 4 commodities up to day 185
do $$
declare
  commodities text[] := array['energy', 'material', 'compute', 'food'];
  base_prices numeric[] := array[30.00, 45.00, 60.00, 20.00];
  c text;
  idx int;
  day int;
  base_p numeric;
  o numeric;
  h numeric;
  l numeric;
  cls numeric;
  vol numeric;
  step_noise numeric;
begin
  for idx in 1..4 loop
    c := commodities[idx];
    base_p := base_prices[idx];
    for day in 155..185 loop
      step_noise := (sin(day * 0.4 + idx) * 3.5) + (cos(day * 0.15) * 2.0);
      o := round(base_p + step_noise, 2);
      cls := round(o + (sin(day * 0.7) * 2.2), 2);
      h := round(greatest(o, cls) + abs(cos(day * 0.3)) * 2.0 + 0.5, 2);
      l := round(least(o, cls) - abs(sin(day * 0.5)) * 1.8 - 0.3, 2);
      vol := round(1000.0 + abs(sin(day * 0.9)) * 1500.0, 0);

      insert into market_ohlc_snapshots (id, commodity, game_day, open_price, high_price, low_price, close_price, volume)
      values (
        'OHLC-' || upper(c) || '-' || day,
        c,
        day,
        o,
        h,
        l,
        cls,
        vol
      ) on conflict (commodity, game_day) do nothing;
    end loop;
  end loop;
end $$;

-- Seed sample open and active futures contracts for player H-0044
insert into commodity_futures_contracts (
  id, seller_human_id, buyer_human_id, commodity, contract_size, strike_price, expiry_game_day, collateral_locked, premium_paid, status
) values
(
  'FUT-ENERGY-101',
  'H-0044',
  null,
  'energy',
  250.00,
  28.50,
  210,
  250.00,
  0.00,
  'open'
),
(
  'FUT-COMPUTE-102',
  'H-0012',
  'H-0044',
  'compute',
  100.00,
  58.00,
  200,
  100.00,
  250.00,
  'matched'
) on conflict (id) do nothing;
