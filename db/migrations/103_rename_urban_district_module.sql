-- Migration 103: use the public name Urban District Module consistently.
-- This is a deliberate correction to the immutable Tier 1 seed, not a
-- gameplay rebalance. Future changes must continue through new migrations.

DROP TRIGGER IF EXISTS building_catalog_original_immutable ON building_catalog;

UPDATE building_catalog
SET name = 'Urban District Module',
    description = 'Foundational city district infrastructure. Additional modules expand the city horizontally through civic proposals.',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 'urban-district-module-t1'
  AND is_original = TRUE
  AND tier = 1;

CREATE TRIGGER building_catalog_original_immutable
BEFORE UPDATE ON building_catalog
FOR EACH ROW EXECUTE FUNCTION earth_prevent_original_catalog_mutation();
