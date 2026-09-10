-- Plan 6: durable scheduler-run observability.

CREATE TABLE IF NOT EXISTS scheduler_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scheduled_time BIGINT NOT NULL,
  worker_instance_id TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ,
  status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'partial', 'busy', 'failed')),
  game_day BIGINT,
  game_minute INTEGER,
  settlement_watermark_before BIGINT,
  settlement_watermark_after BIGINT,
  backlog_before BIGINT,
  backlog_after BIGINT,
  settlement_days_processed INTEGER NOT NULL DEFAULT 0,
  actions_processed INTEGER NOT NULL DEFAULT 0,
  market_batches_processed INTEGER NOT NULL DEFAULT 0,
  outbox_events_delivered INTEGER NOT NULL DEFAULT 0,
  error_stage TEXT,
  error_message TEXT
);
CREATE INDEX IF NOT EXISTS scheduler_runs_started_idx ON scheduler_runs(started_at DESC);
CREATE INDEX IF NOT EXISTS scheduler_runs_status_idx ON scheduler_runs(status, started_at DESC);
