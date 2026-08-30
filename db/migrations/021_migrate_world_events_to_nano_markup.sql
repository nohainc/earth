-- Migration 021: Migrate world_events.details to Nano Markup TEXT and add correlation_id

alter table world_events
  add column if not exists correlation_id text;

-- Backfill correlation_id from details if stored as JSON
update world_events
set correlation_id = details->>'correlationId'
where correlation_id is null and details::text like '%correlationId%';

alter table world_events
  alter column details type text using details::text;

create index if not exists world_events_correlation_idx
  on world_events(event_type, correlation_id)
  where correlation_id is not null;
