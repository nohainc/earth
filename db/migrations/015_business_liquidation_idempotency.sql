alter table bankruptcy_events add column if not exists correlation_id text;
create unique index if not exists bankruptcy_events_institution_correlation_idx
  on bankruptcy_events(institution_id, correlation_id)
  where correlation_id is not null;
