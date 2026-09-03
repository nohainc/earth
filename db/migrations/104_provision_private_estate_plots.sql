-- Migration 104: every active human receives one foundational private estate.
-- Estate plots are personal, city-independent, active at Tier 1, and are
-- intentionally absent from the normal building catalog UI.

-- Estate deeds do not consume a city slot. Relax the legacy constraint before
-- provisioning them; keep the upper bound enforced for all building types.
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_slot_footprint_check;
ALTER TABLE buildings DROP CONSTRAINT IF EXISTS chk_buildings_slot_footprint;
ALTER TABLE buildings ADD CONSTRAINT buildings_slot_footprint_check
  CHECK (slot_footprint >= 0 AND slot_footprint <= 12);

INSERT INTO buildings (
  id, city_id, owner_id, catalog_id, building_type, name, tier, condition,
  slot_footprint, ownership_class, operating_policy, auto_repair_enabled,
  upkeep_energy, upkeep_food, upkeep_materials, upkeep_components,
  upkeep_compute, daily_operating_credits, resource_output_type,
  resource_output_amount, construction_started_game_day,
  construction_complete_game_day, construction_progress, status, created_game_day
)
SELECT
  'BLD-ESTATE-' || h.id,
  NULL,
  h.id,
  c.id,
  c.building_type,
  c.name,
  c.tier,
  100,
  c.slot_footprint,
  c.ownership_class,
  'balanced',
  TRUE,
  c.upkeep_energy,
  c.upkeep_food,
  c.upkeep_materials,
  c.upkeep_components,
  c.upkeep_compute,
  c.operating_credits,
  NULL,
  0,
  COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 1),
  COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 1),
  100,
  'active',
  COALESCE((SELECT game_day FROM world_state WHERE id = 'WORLD'), 1)
FROM humans h
JOIN building_catalog c
  ON c.id = 'private-estate-plot-t1'
WHERE h.life_status = 'active'
  AND h.account_status = 'active'
  AND NOT EXISTS (
    SELECT 1
    FROM buildings b
    WHERE b.owner_id = h.id
      AND b.building_type = 'private-estate-plot'
      AND b.status NOT IN ('closed', 'foreclosed')
  )
ON CONFLICT (id) DO NOTHING;
