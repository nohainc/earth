-- Death & Continuity V2 Plan 35.
-- House succession is now the only supported succession architecture.

ALTER TABLE succession_plans
  DROP COLUMN IF EXISTS successor_human_id,
  DROP COLUMN IF EXISTS estate_period_days;

COMMENT ON TABLE succession_plans IS
  'Legacy compatibility record retained for historical reads; active succession uses house_succession_plans.';
