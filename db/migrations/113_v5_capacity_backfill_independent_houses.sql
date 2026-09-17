-- Extend the resumable V5 capacity backfill with an independent-House cursor.
-- Independent Houses are Earth-direct capacity principals and must not be
-- omitted simply because the corporation cursor has been exhausted.

ALTER TABLE v5_capacity_backfill_runs
  ADD COLUMN IF NOT EXISTS cursor_house_id TEXT;
