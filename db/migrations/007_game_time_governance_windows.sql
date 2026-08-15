-- Governance windows are authoritative in game time. Existing real-time
-- timestamps remain as historical compatibility fields and audit metadata.
alter table proposals add column if not exists closes_game_day bigint;
alter table proposals add column if not exists closes_game_minute integer;
alter table proposals add column if not exists implementation_game_day bigint;
alter table proposals add column if not exists implementation_game_minute integer;

with clock as (
  select game_day, game_minute
  from world_state
  where id = 'WORLD'
), projected as (
  select
    p.id,
    (clock.game_day * 1440 + clock.game_minute + greatest(0, floor(extract(epoch from (p.closes_at - current_timestamp)) / 60)))::bigint as close_absolute_minute,
    case
      when p.implementation_at is null then null
      else (clock.game_day * 1440 + clock.game_minute + greatest(0, floor(extract(epoch from (p.implementation_at - current_timestamp)) / 60)))::bigint
    end as implementation_absolute_minute
  from proposals p
  cross join clock
  where p.closes_game_day is null
)
update proposals p
set closes_game_day = floor(projected.close_absolute_minute / 1440.0)::bigint,
    closes_game_minute = mod(projected.close_absolute_minute, 1440)::integer,
    implementation_game_day = case when projected.implementation_absolute_minute is null then null else floor(projected.implementation_absolute_minute / 1440.0)::bigint end,
    implementation_game_minute = case when projected.implementation_absolute_minute is null then null else mod(projected.implementation_absolute_minute, 1440)::integer end
from projected
where p.id = projected.id;

alter table proposals drop constraint if exists proposals_closes_game_minute_check;
alter table proposals add constraint proposals_closes_game_minute_check check (closes_game_minute between 0 and 1439);
alter table proposals drop constraint if exists proposals_implementation_game_minute_check;
alter table proposals add constraint proposals_implementation_game_minute_check check (implementation_game_minute between 0 and 1439);
create index if not exists proposals_game_deadline_idx on proposals(status, closes_game_day, closes_game_minute);
