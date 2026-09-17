-- EARTH ACTIVE MIGRATION: V5 restructuring submissions are replay-safe at the database boundary.
ALTER TABLE v5_corporation_restructuring_plans
  ADD COLUMN IF NOT EXISTS correlation_id TEXT;

UPDATE v5_corporation_restructuring_plans
SET correlation_id = id
WHERE correlation_id IS NULL;

ALTER TABLE v5_corporation_restructuring_plans
  ALTER COLUMN correlation_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS v5_restructuring_plan_correlation_uq
  ON v5_corporation_restructuring_plans(correlation_id);
