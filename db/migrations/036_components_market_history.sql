-- Give Components the same persistent price-history coverage as the other
-- commodities so the spot-market chart is meaningful for every listed row.
alter table market_ohlc_snapshots
  drop constraint if exists market_ohlc_snapshots_commodity_check;

alter table market_ohlc_snapshots
  add constraint market_ohlc_snapshots_commodity_check
  check (commodity in ('energy', 'material', 'compute', 'food', 'components'));

with current_world as (
  select game_day from world_state where id = 'WORLD'
), series as (
  select current_world.game_day + offset_day as game_day, offset_day
  from current_world cross join generate_series(-29, 0) as offset_day
), prices as (
  select
    game_day,
    round((118.70 + sin(game_day * 0.37) * 8.40 + cos(game_day * 0.11) * 3.10)::numeric, 2) as open_price,
    round((118.70 + sin(game_day * 0.37) * 8.40 + cos(game_day * 0.11) * 3.10 + sin(game_day * 0.71) * 4.60)::numeric, 2) as close_price,
    offset_day
  from series
)
insert into market_ohlc_snapshots (
  id, commodity, game_day, open_price, high_price, low_price, close_price, volume
)
select
  'OHLC-COMPONENTS-' || game_day,
  'components',
  game_day,
  open_price,
  round((greatest(open_price, close_price) + 2.40)::numeric, 2),
  round((least(open_price, close_price) - 2.10)::numeric, 2),
  close_price,
  round((900 + abs(sin(game_day * 0.53)) * 1800)::numeric, 0)
from prices
on conflict (commodity, game_day) do nothing;
