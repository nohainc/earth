-- Migration 105: estate vertical tiers are created only by corporation research.
-- Remove any unresearched estate blueprints and stale unlock metadata. A tier
-- already referenced by a built estate is retained so the catalog FK remains
-- valid and that historical building can still be displayed.

DELETE FROM corporation_building_unlocks
WHERE catalog_id IN (
  SELECT id FROM building_catalog
  WHERE building_type = 'private-estate-plot' AND tier > 1
);

DELETE FROM corporation_building_research_projects
WHERE catalog_id IN (
  SELECT id FROM building_catalog
  WHERE building_type = 'private-estate-plot' AND tier > 1
);

DELETE FROM building_catalog c
WHERE c.building_type = 'private-estate-plot'
  AND c.tier > 1
  AND NOT EXISTS (
    SELECT 1 FROM buildings b WHERE b.catalog_id = c.id
  );
