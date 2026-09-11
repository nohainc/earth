-- Plan 13: the building catalog no longer models CREDIT as a building output.
-- Buildings provide physical production or service capacity; customer-funded
-- revenue is settled separately.

ALTER TABLE building_catalog DROP COLUMN IF EXISTS output_credits;
