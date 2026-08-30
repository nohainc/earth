-- EARTH PostgreSQL Migration 030: Net Worth Snapshots, Multi-Asset Allocation & Financial History
-- Tracks 4-pillar asset portfolios (Liquid Credits, Commodities, Corporate Equity, Real Estate Concessions).

create table if not exists net_worth_snapshots (
  id text primary key,
  human_id text not null references humans(id),
  game_day bigint not null check (game_day > 0),
  liquid_credits numeric(20,2) not null default 0,
  commodity_valuation numeric(20,2) not null default 0,
  equity_valuation numeric(20,2) not null default 0,
  real_estate_valuation numeric(20,2) not null default 0,
  total_net_worth numeric(20,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint uq_net_worth_human_day unique (human_id, game_day)
);

create index if not exists idx_net_worth_human_day on net_worth_snapshots(human_id, game_day desc);

-- Seed 30-day historical net-worth trajectory for founding player H-0044
do $$
declare
  day int;
  base_cash numeric := 15000.00;
  base_comm numeric := 8000.00;
  base_eq numeric := 25000.00;
  base_re numeric := 12000.00;
  c_val numeric;
  m_val numeric;
  e_val numeric;
  r_val numeric;
  tot numeric;
begin
  if exists (select 1 from humans where id = 'H-0044') then
    for day in 155..185 loop
      c_val := round((base_cash + ((day - 155) * 850.00) + (sin(day * 0.5) * 1200.00)::numeric)::numeric, 2);
      m_val := round((base_comm + ((day - 155) * 420.00) + (cos(day * 0.3) * 800.00)::numeric)::numeric, 2);
      e_val := round((base_eq + ((day - 155) * 1450.00) + (sin(day * 0.8) * 2500.00)::numeric)::numeric, 2);
      r_val := round((base_re + ((day - 155) * 600.00))::numeric, 2);
      tot := c_val + m_val + e_val + r_val;

      insert into net_worth_snapshots (
        id, human_id, game_day, liquid_credits, commodity_valuation, equity_valuation, real_estate_valuation, total_net_worth
      ) values (
        'NW-H0044-' || day,
        'H-0044',
        day,
        c_val,
        m_val,
        e_val,
        r_val,
        tot
      ) on conflict (human_id, game_day) do update set
        liquid_credits = excluded.liquid_credits,
        commodity_valuation = excluded.commodity_valuation,
        equity_valuation = excluded.equity_valuation,
        real_estate_valuation = excluded.real_estate_valuation,
        total_net_worth = excluded.total_net_worth;
    end loop;
  end if;
end $$;
