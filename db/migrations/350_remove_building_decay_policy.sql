-- Plan 13: policy no longer models building deterioration.
-- Operating policy affects output and cost only; maintenance is included in
-- normal operating expense and never creates a repair lifecycle.

ALTER TABLE economic_policy_rules
  DROP COLUMN IF EXISTS decay_multiplier;
