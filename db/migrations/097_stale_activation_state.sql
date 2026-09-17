-- EARTH ACTIVE MIGRATION: preserve stale constitutional activations distinctly from failures.

ALTER TABLE v5_governance_activation_queue DROP CONSTRAINT IF EXISTS v5_governance_activation_queue_status_check;
ALTER TABLE v5_governance_activation_queue ADD CONSTRAINT v5_governance_activation_queue_status_check
  CHECK (status IN ('PENDING','APPLIED','FAILED','STALE'));
