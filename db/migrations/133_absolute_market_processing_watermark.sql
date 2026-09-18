-- EARTH ACTIVE MIGRATION: absolute market processing watermark

CREATE TABLE IF NOT EXISTS market_processing_control (
  id TEXT PRIMARY KEY,
  processed_through_market_batch BIGINT NOT NULL DEFAULT -1 CHECK (processed_through_market_batch >= -1),
  status TEXT NOT NULL DEFAULT 'IDLE' CHECK (status IN ('IDLE', 'PROCESSING', 'FAILED')),
  current_market_batch BIGINT,
  lease_owner TEXT,
  lease_expires_at TIMESTAMPTZ,
  error_message TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO market_processing_control (id)
VALUES ('WORLD')
ON CONFLICT (id) DO NOTHING;

CREATE INDEX IF NOT EXISTS market_processing_control_lease_idx
  ON market_processing_control (status, lease_expires_at);
