-- EARTH ACTIVE MIGRATION: align the V5 House statement projection with the
-- canonical delinquency state machine used during daily settlement.
ALTER TABLE house_capacity_statements_v5
  DROP CONSTRAINT IF EXISTS house_capacity_statements_v5_delinquency_status_check;

ALTER TABLE house_capacity_statements_v5
  ADD CONSTRAINT house_capacity_statements_v5_delinquency_status_check
  CHECK (delinquency_status IN (
    'CURRENT',
    'ARREARS',
    'GRACE',
    'RESTRICTED',
    'SUSPENDED',
    'RESOLVING',
    'EXPANSION_BLOCKED',
    'PRODUCTIVE_CAPACITY_SUSPENDED'
  ));
