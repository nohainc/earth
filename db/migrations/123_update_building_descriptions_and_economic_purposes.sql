-- Migration 123: Update building catalog descriptions and primary economic purposes in PostgreSQL database.

DROP TRIGGER IF EXISTS building_catalog_original_immutable ON building_catalog;

-- 1. Update Urban District Module description and economic purpose
UPDATE building_catalog
SET description = 'Expands city borders, infrastructure, and citizen capacity.',
    primary_economic_purpose = 'Municipal Land & Citizen Capacity Expansion',
    updated_at = CURRENT_TIMESTAMP
WHERE building_type = 'urban-district-module'
   OR id LIKE 'urban-district-module%';

-- 2. Ensure all other primary economic purposes and descriptions are consistently updated
UPDATE building_catalog
SET primary_economic_purpose = 'Municipal Land & Citizen Capacity Expansion'
WHERE building_type = 'district-expansion';

CREATE TRIGGER building_catalog_original_immutable
BEFORE UPDATE ON building_catalog
FOR EACH ROW EXECUTE FUNCTION earth_prevent_original_catalog_mutation();
