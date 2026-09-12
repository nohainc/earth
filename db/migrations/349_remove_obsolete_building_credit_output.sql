-- Plan 13: the building catalog no longer models CREDIT as a building output.
-- Buildings provide physical production or service capacity; customer-funded
-- revenue is settled separately.

-- These balance/read-model views previously used building_catalog.* and thus
-- carried an implicit dependency on the obsolete output_credits column.
-- Remove the stale projections before dropping that source field; the balance
-- report can be regenerated from the canonical catalog after cutover.
DROP VIEW IF EXISTS building_operating_cost_model CASCADE;
DROP VIEW IF EXISTS building_tier_balance_flags CASCADE;
DROP VIEW IF EXISTS building_economic_balance_model CASCADE;

ALTER TABLE building_catalog DROP COLUMN IF EXISTS output_credits;
