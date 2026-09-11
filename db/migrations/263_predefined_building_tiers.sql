-- Building Economy V2 Plan 9: authored building tiers.
-- Research may unlock a catalog row, but it must never manufacture shared
-- building economics from formulas at runtime.

ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_tier_range_ck CHECK (tier BETWEEN 1 AND 5);

CREATE UNIQUE INDEX IF NOT EXISTS building_catalog_type_tier_uq
  ON building_catalog (building_type, tier);

COMMENT ON INDEX building_catalog_type_tier_uq IS
  'Each building type has at most one authored economic definition per tier; tiers 1 through 5 are predefined data.';
