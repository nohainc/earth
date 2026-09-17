-- EARTH ACTIVE MIGRATION: typed constitutional change-set proposal action.

ALTER TABLE v5_governance_proposals DROP CONSTRAINT IF EXISTS v5_governance_proposals_action_type_check;
ALTER TABLE v5_governance_proposals ADD CONSTRAINT v5_governance_proposals_action_type_check
  CHECK (action_type IN ('CONSTITUTION_AMENDMENT','EARTH_CAPACITY_POLICY','CORPORATION_HOUSE_RATE','PROGRESSIVE_SCHEDULE','CORPORATION_ADMISSION_POLICY'));
