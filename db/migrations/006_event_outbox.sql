-- Transactional side-effect queue. Domain mutations write here in the same
-- PostgreSQL transaction as their ledger/event changes; delivery is retried
-- by the scheduled Worker until the event is acknowledged.
create table if not exists event_outbox (
  id uuid primary key,
  event_key text not null unique,
  topic text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  payload jsonb not null default '{}',
  available_at timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  locked_at timestamptz,
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);
create index if not exists event_outbox_pending_idx
  on event_outbox(available_at, created_at)
  where processed_at is null;
create index if not exists event_outbox_aggregate_idx
  on event_outbox(aggregate_type, aggregate_id, created_at);
