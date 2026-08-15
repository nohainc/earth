-- Correlation IDs remain opaque idempotency keys and are not restricted to UUIDs.
alter table ledger_entries alter column correlation_id type text using correlation_id::text;
