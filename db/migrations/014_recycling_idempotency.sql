-- Make destructive machine recycling safely replayable.
alter table recycling_events add column if not exists correlation_id text;
create unique index if not exists recycling_events_machine_correlation_idx
  on recycling_events(machine_id, correlation_id)
  where correlation_id is not null;
