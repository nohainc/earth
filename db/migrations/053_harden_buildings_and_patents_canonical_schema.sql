-- Migration 053: Canonical Building-Centric Ownership, Robust Patent Licensing Constraints, and Economic Unification

-- 1. Backfill and enforce canonical ownership_class on buildings
UPDATE buildings
SET ownership_class = CASE
  WHEN ownership_class IS NOT NULL AND ownership_class <> '' THEN ownership_class
  WHEN ownership_type = 'municipal' THEN 'civic'
  WHEN ownership_type = 'public' THEN 'public_investment'
  ELSE 'private'
END
WHERE ownership_class IS NULL OR ownership_class = '';

ALTER TABLE buildings
  ALTER COLUMN ownership_class SET NOT NULL,
  ALTER COLUMN ownership_class SET DEFAULT 'private',
  ALTER COLUMN ownership_type DROP NOT NULL,
  ALTER COLUMN max_staff_slots DROP NOT NULL,
  ALTER COLUMN base_revenue_crd DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_buildings_ownership_class'
  ) THEN
    ALTER TABLE buildings ADD CONSTRAINT chk_buildings_ownership_class
      CHECK (ownership_class IN ('private', 'civic', 'public_investment'));
  END IF;
END $$;

-- 2. Add validation constraints on building patent licenses safely
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_bld_patent_lic_type'
  ) THEN
    ALTER TABLE building_patent_licenses ADD CONSTRAINT chk_bld_patent_lic_type
      CHECK (license_type IN ('corporate_member', 'private_building', 'city_civic'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_bld_patent_lic_status'
  ) THEN
    ALTER TABLE building_patent_licenses ADD CONSTRAINT chk_bld_patent_lic_status
      CHECK (status IN ('active', 'renewal_window', 'expired'));
  END IF;
END $$;

-- 3. Prevent duplicate active licenses for the same building and patent
CREATE UNIQUE INDEX IF NOT EXISTS uq_building_patent_active
  ON building_patent_licenses (building_id, patent_id)
  WHERE status IN ('active', 'renewal_window') AND building_id IS NOT NULL;

-- 4. Prevent duplicate active city-wide civic licenses for the same city and patent
CREATE UNIQUE INDEX IF NOT EXISTS uq_city_patent_active
  ON building_patent_licenses (city_id, patent_id)
  WHERE status IN ('active', 'renewal_window') AND license_type = 'city_civic' AND city_id IS NOT NULL;
