-- EARTH ACTIVE MIGRATION: canonical building family and tier formula metadata

ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS family_code TEXT;
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS tier_formula_version TEXT NOT NULL DEFAULT 'building-formula-v1';

UPDATE building_catalog
   SET family_code = CASE
     WHEN code ~ '_t[1-5]$' THEN regexp_replace(code, '_t[1-5]$', '')
     ELSE code
   END
 WHERE family_code IS NULL;

ALTER TABLE building_catalog ALTER COLUMN family_code SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS building_catalog_family_tier_uq
  ON building_catalog (family_code, tier);

CREATE INDEX IF NOT EXISTS building_catalog_formula_version_idx
  ON building_catalog (family_code, tier_formula_version, tier);
