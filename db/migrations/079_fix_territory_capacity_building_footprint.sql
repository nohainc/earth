-- EARTH ACTIVE MIGRATION: fix territory capacity footprint source
-- Building footprint is defined by building_catalog and buildings reference it
-- through catalog_id. Keep the baseline immutable and replace the function
-- forward so corporation formation and construction refreshes work on all DBs.

CREATE OR REPLACE FUNCTION earth_refresh_territory_capacity(
  p_territory_id TEXT,
  p_game_day BIGINT
)
RETURNS territory_capacity_state
LANGUAGE plpgsql
AS $$
DECLARE result territory_capacity_state;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM territories WHERE id = p_territory_id) THEN
    RAISE EXCEPTION 'Territory not found';
  END IF;

  INSERT INTO territory_capacity_state (
    territory_id, game_day, active_house_count, house_capacity, population_capacity,
    private_slot_capacity, public_slot_capacity, private_slots_used, public_slots_used,
    housing_capacity, health_capacity, energy_capacity, connectivity_capacity,
    service_capacity, updated_at
  )
  SELECT
    p_territory_id,
    p_game_day,
    (SELECT COUNT(*)::INTEGER FROM house_affiliations ha
      WHERE ha.primary_territory_id = p_territory_id AND ha.status = 'ACTIVE'),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code IN ('POPULATION_CAPACITY', 'HOUSE_CAPACITY')), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code IN ('POPULATION_CAPACITY', 'HOUSE_CAPACITY')), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'PRIVATE_SLOTS'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'PUBLIC_SLOTS'), 0),
    COALESCE((SELECT SUM(bc.slot_footprint)::BIGINT
                FROM buildings b
                JOIN building_catalog bc ON bc.id = b.catalog_id
                JOIN owner_registry o ON o.economic_id = b.owner_economic_id
               WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND o.owner_type = 'HOUSE'), 0),
    COALESCE((SELECT SUM(bc.slot_footprint)::BIGINT
                FROM buildings b
                JOIN building_catalog bc ON bc.id = b.catalog_id
                JOIN owner_registry o ON o.economic_id = b.owner_economic_id
               WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND o.owner_type = 'CORPORATION'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'HOUSING_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'HEALTH_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'ENERGY_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'CONNECTIVITY_CAPACITY'), 0),
    COALESCE((SELECT jsonb_object_agg(service_key, service_total) FROM (
      SELECT COALESCE(NULLIF(bc.service_type, ''), 'UNSPECIFIED') AS service_key,
             SUM(bc.service_capacity_units)::BIGINT AS service_total
        FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
       WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND bc.service_capacity_units > 0
       GROUP BY COALESCE(NULLIF(bc.service_type, ''), 'UNSPECIFIED')
    ) services), '{}'::jsonb),
    now()
  FROM buildings b
  LEFT JOIN building_catalog_effects e ON e.catalog_id = b.catalog_id
  WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE'
  RETURNING * INTO result;
  RETURN result;
END;
$$;
