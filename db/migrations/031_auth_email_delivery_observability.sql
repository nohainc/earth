CREATE TABLE IF NOT EXISTS auth_email_deliveries (
  id TEXT PRIMARY KEY,
  correlation_id TEXT NOT NULL,
  human_id TEXT NOT NULL,
  recipient_masked TEXT NOT NULL,
  action TEXT NOT NULL,
  status TEXT NOT NULL,
  provider_message_id TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auth_email_deliveries_created ON auth_email_deliveries (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_email_deliveries_correlation ON auth_email_deliveries (correlation_id);
