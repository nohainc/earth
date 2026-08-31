-- Migration 088: Centralized Application & Client Error Logging
--
-- Captures rich telemetry and diagnostic exception logs from both
-- the Cloudflare backend APIs and the client-side Flutter application.

CREATE TABLE IF NOT EXISTS app_error_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  human_id TEXT REFERENCES humans(id) ON DELETE SET NULL,
  source TEXT NOT NULL, -- 'backend_api' | 'client_flutter' | 'scheduler'
  endpoint TEXT,
  status_code INTEGER,
  error_code TEXT,
  error_message TEXT NOT NULL,
  stack_trace TEXT,
  context_data JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_app_error_logs_created_at
  ON app_error_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_app_error_logs_human_id
  ON app_error_logs (human_id, created_at DESC)
  WHERE human_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_app_error_logs_source
  ON app_error_logs (source, created_at DESC);
