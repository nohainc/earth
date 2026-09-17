-- EARTH ACTIVE MIGRATION: resumable V5 capacity backfill/reconciliation state.
-- Backfill writes shadow capacity facts only; it never creates obligations or
-- economic transactions for historical days.

CREATE TABLE v5_capacity_backfill_runs (
  id TEXT PRIMARY KEY,
  source_game_day BIGINT NOT NULL CHECK (source_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'RUNNING' CHECK (status IN ('RUNNING','COMPLETED','FAILED')),
  cursor_corporation_id TEXT,
  corporations_processed INTEGER NOT NULL DEFAULT 0 CHECK (corporations_processed >= 0),
  houses_processed INTEGER NOT NULL DEFAULT 0 CHECK (houses_processed >= 0),
  building_units_processed BIGINT NOT NULL DEFAULT 0 CHECK (building_units_processed >= 0),
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  UNIQUE (source_game_day)
);

CREATE INDEX v5_capacity_backfill_runs_status_idx
  ON v5_capacity_backfill_runs (status, source_game_day);
