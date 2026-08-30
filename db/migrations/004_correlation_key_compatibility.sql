-- D1 correlation IDs are opaque idempotency keys, not UUIDs.
alter table ledger_entries alter column correlation_id type text using correlation_id::text;
