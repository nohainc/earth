CREATE TABLE scheduler_tick_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_day INTEGER NOT NULL,
  engine TEXT NOT NULL,
  rows_processed INTEGER DEFAULT 0,
  duration_ms INTEGER,
  status TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok','error','skipped')),
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_scheduler_tick_logs_day ON scheduler_tick_logs(game_day DESC, engine);
