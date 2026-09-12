-- Repair indexes lost during the Economy V2 entry-table partitioning cutover.
-- The old index names were still attached to the temporary pre-partition table,
-- so CREATE INDEX IF NOT EXISTS skipped them before that table was removed.

CREATE INDEX IF NOT EXISTS economic_entries_transaction_idx
  ON economic_entries (transaction_id, id);

CREATE INDEX IF NOT EXISTS economic_entries_account_day_idx
  ON economic_entries (account_id, game_day DESC, id DESC);

CREATE INDEX IF NOT EXISTS economic_entries_reason_idx
  ON economic_entries (reason_code, game_day DESC);
