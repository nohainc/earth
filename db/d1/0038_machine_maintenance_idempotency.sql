ALTER TABLE maintenance_events ADD COLUMN correlation_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_maintenance_events_machine_correlation
  ON maintenance_events (machine_id, correlation_id)
  WHERE correlation_id IS NOT NULL;
