-- Retire the machine economy. Buildings are now the sole productive assets.

DELETE FROM ownership_events WHERE asset_type = 'MACHINE' OR reason_type IN ('machine_acquisition', 'machine_upgrade', 'machine_sale', 'machine_liquidation', 'recycling');
DELETE FROM ledger_entries WHERE reason_type IN ('machine_acquisition', 'machine_upgrade', 'machine_sale', 'machine_liquidation', 'business_depreciation');
DELETE FROM notifications WHERE entity_id LIKE 'M-%' OR body ILIKE '%machine%';

DROP TABLE IF EXISTS municipal_labor_pool;
-- The building_staff_assignments table is not present in the current schema. These statements are removed.
-- DELETE FROM building_staff_assignments WHERE machine_id IS NOT NULL;
-- ALTER TABLE building_staff_assignments DROP CONSTRAINT IF EXISTS uq_building_machine_slot;
-- ALTER TABLE building_staff_assignments DROP CONSTRAINT IF EXISTS building_staff_assignments_staff_type_check;
-- ALTER TABLE building_staff_assignments DROP COLUMN IF EXISTS machine_id;
-- ALTER TABLE building_staff_assignments DROP COLUMN IF EXISTS staff_type;

DROP TABLE IF EXISTS business_assets;
DROP TABLE IF EXISTS maintenance_events;
DROP TABLE IF EXISTS production_events;
DROP TABLE IF EXISTS recycling_events;
DROP TABLE IF EXISTS machine_upgrade_events;
DROP TABLE IF EXISTS machine_sales;
DROP TABLE IF EXISTS machine_acquisitions;
DROP TABLE IF EXISTS machines;
