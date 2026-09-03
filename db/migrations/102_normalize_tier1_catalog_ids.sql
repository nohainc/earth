-- Migration 102: normalize every immutable Tier 1 blueprint to <type>-t1.

DROP TRIGGER IF EXISTS building_catalog_original_immutable ON building_catalog;
DROP INDEX IF EXISTS building_catalog_original_type_idx;

CREATE TEMP TABLE tier1_sources AS
SELECT * FROM building_catalog
WHERE tier = 1 AND is_original = true AND id NOT LIKE '%-t1';

-- Existing built records already use the suffixed IDs. Copy the new baseline
-- metadata onto those canonical rows before removing duplicate unsuffixed rows.
UPDATE building_catalog target SET
  building_type=source.building_type, name=source.name, category=source.category,
  ownership_class=source.ownership_class, slot_footprint=source.slot_footprint,
  cost_credits=source.cost_credits, cost_energy=source.cost_energy, cost_food=source.cost_food,
  cost_materials=source.cost_materials, cost_components=source.cost_components, cost_compute=source.cost_compute,
  output_credits=source.output_credits, output_energy=source.output_energy, output_food=source.output_food,
  output_materials=source.output_materials, output_components=source.output_components, output_compute=source.output_compute,
  upkeep_credits=source.upkeep_credits, upkeep_energy=source.upkeep_energy, upkeep_food=source.upkeep_food,
  upkeep_materials=source.upkeep_materials, upkeep_components=source.upkeep_components, upkeep_compute=source.upkeep_compute,
  operating_credits=source.operating_credits, operating_energy=source.operating_energy, operating_food=source.operating_food,
  operating_materials=source.operating_materials, operating_components=source.operating_components, operating_compute=source.operating_compute,
  description=source.description, construction_days=source.construction_days, construction_minutes=source.construction_minutes,
  is_active=source.is_active, research_project_id=NULL, effects=source.effects, building_role=source.building_role,
  is_original=true, dividend_share_percent=source.dividend_share_percent, updated_at=CURRENT_TIMESTAMP
FROM tier1_sources source
WHERE target.id = source.id || '-t1';

DELETE FROM building_catalog source
WHERE source.id IN (SELECT id FROM tier1_sources)
  AND EXISTS (SELECT 1 FROM building_catalog target WHERE target.id = source.id || '-t1');

UPDATE building_catalog SET
  id = id || '-t1',
  updated_at = CURRENT_TIMESTAMP
WHERE tier = 1 AND is_original = true AND id NOT LIKE '%-t1';

UPDATE building_catalog SET prev_catalog_id=NULL, next_catalog_id=NULL
WHERE tier=1 AND is_original=true;

CREATE UNIQUE INDEX building_catalog_original_type_idx
  ON building_catalog(building_type) WHERE is_original=true AND tier=1;

CREATE TRIGGER building_catalog_original_immutable BEFORE UPDATE ON building_catalog
FOR EACH ROW EXECUTE FUNCTION earth_prevent_original_catalog_mutation();
