-- Migration 053: Canonical Building-Centric Ownership, Robust Patent Licensing Constraints, and Economic Unification

-- 1. Backfill and enforce canonical ownership_class on buildings
UPDATE buildings
SET ownership_class = CASE
  WHEN ownership_class IS NOT NULL AND ownership_class <> '' THEN ownership_class
  WHEN ownership_type = 'municipal' THEN 'civic'
  WHEN ownership_type = 'public' THEN 'public_investment'
  ELSE 'private'
END;

ALTER TABLE buildings
  ALTER COLUMN ownership_class SET NOT NULL,
  ALTER COLUMN ownership_class SET DEFAULT 'private';

-- 2. Add validation constraints on building patent licenses
ALTER TABLE building_patent_licenses
  ADD CONSTRAINT chk_bld_patent_lic_type CHECK (license_type IN ('corporate_member', 'private_building', 'city_civic')),
  ADD CONSTRAINT chk_bld_patent_lic_status CHECK (status IN ('active', 'renewal_window', 'expired'));

-- 3. Prevent duplicate active licenses for the same building and patent
CREATE UNIQUE INDEX IF NOT EXISTS uq_building_patent_active
  ON building_patent_licenses (building_id, patent_id)
  WHERE status IN ('active', 'renewal_window') AND building_id IS NOT NULL;
