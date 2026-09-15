-- EARTH ACTIVE MIGRATION: V4-115 explicit building economic roles

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS economic_role TEXT NOT NULL DEFAULT 'ESTATE';

ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_economic_role_check;

ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_economic_role_check
  CHECK (economic_role IN ('PRODUCER', 'TRANSFORMER', 'SERVICE', 'INFRASTRUCTURE', 'ESTATE'));

UPDATE building_catalog
   SET economic_role = CASE
     WHEN ownership_scope = 'PUBLIC' THEN 'INFRASTRUCTURE'
     WHEN service_type IS NOT NULL AND service_capacity_units > 0 THEN 'SERVICE'
     WHEN EXISTS (
       SELECT 1 FROM building_catalog_resource_flows f
        WHERE f.catalog_id = building_catalog.id
          AND f.operating_input_units > 0
     ) AND EXISTS (
       SELECT 1 FROM building_catalog_resource_flows f
        WHERE f.catalog_id = building_catalog.id
          AND f.operating_output_units > 0
     ) THEN 'TRANSFORMER'
     WHEN EXISTS (
       SELECT 1 FROM building_catalog_resource_flows f
        WHERE f.catalog_id = building_catalog.id
          AND f.operating_output_units > 0
     ) THEN 'PRODUCER'
     ELSE 'ESTATE'
   END;

CREATE INDEX IF NOT EXISTS building_catalog_economic_role_idx
  ON building_catalog (economic_role);
