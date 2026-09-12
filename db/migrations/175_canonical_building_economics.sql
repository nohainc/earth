-- Economy V2 Plan 26: one DB-catalog-backed building economics calculator.

CREATE OR REPLACE FUNCTION earth_calculate_building_economics(p_building_id TEXT)
RETURNS TABLE (
  asset_id SMALLINT,
  asset_code TEXT,
  output_units NUMERIC,
  upkeep_units NUMERIC,
  operating_units NUMERIC,
  effective_output_multiplier NUMERIC,
  effective_cost_multiplier NUMERIC
)
LANGUAGE SQL
STABLE
AS $$
  SELECT v.asset_id,
         v.asset_code,
         v.output_units,
         v.upkeep_units,
         v.operating_units,
         CASE lower(COALESCE(b.operating_policy, 'balanced'))
           WHEN 'high_output' THEN 1.30
           WHEN 'frugal' THEN 0.75
           WHEN 'eco_reserve' THEN 0.75
           WHEN 'halted' THEN 0.00
           ELSE 1.00
         END::NUMERIC AS effective_output_multiplier,
         CASE lower(COALESCE(b.operating_policy, 'balanced'))
           WHEN 'high_output' THEN 1.40
           WHEN 'frugal' THEN 0.70
           WHEN 'eco_reserve' THEN 0.70
           WHEN 'halted' THEN 0.20
           ELSE 1.00
         END::NUMERIC AS effective_cost_multiplier
  FROM buildings b
  JOIN building_catalog bc
    ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  CROSS JOIN LATERAL (VALUES
    (1::SMALLINT, 'CREDIT'::TEXT,    0,                                   COALESCE(bc.upkeep_credits, 0),    COALESCE(bc.operating_credits, 0)),
    (2::SMALLINT, 'MATERIAL'::TEXT,  COALESCE(bc.output_materials, 0),  COALESCE(bc.upkeep_materials, 0),  COALESCE(bc.operating_materials, 0)),
    (3::SMALLINT, 'COMPONENTS'::TEXT,COALESCE(bc.output_components, 0), COALESCE(bc.upkeep_components, 0), COALESCE(bc.operating_components, 0)),
    (4::SMALLINT, 'ENERGY'::TEXT,    COALESCE(bc.output_energy, 0),    COALESCE(bc.upkeep_energy, 0),    COALESCE(bc.operating_energy, 0)),
    (5::SMALLINT, 'COMPUTE'::TEXT,   COALESCE(bc.output_compute, 0),   COALESCE(bc.upkeep_compute, 0),   COALESCE(bc.operating_compute, 0)),
    (6::SMALLINT, 'FOOD'::TEXT,      COALESCE(bc.output_food, 0),      COALESCE(bc.upkeep_food, 0),      COALESCE(bc.operating_food, 0))
  ) AS v(asset_id, asset_code, output_units, upkeep_units, operating_units)
  WHERE b.id = p_building_id;
$$;

-- The former migration dynamically rewrote the legacy rate-history function to
-- include building condition and wear. That rewrite was brittle and is no
-- longer part of the V2 architecture: Building V2 owns its own physical
-- settlement and does not expose condition-based economics.

-- Rebuild profiles from the canonical calculator. Credit remains excluded
-- from accelerated profile posting until the safe-profile gate is removed,
-- but all physical-resource arithmetic now uses independent output/cost
-- multipliers.
CREATE OR REPLACE FUNCTION earth_rebuild_dirty_profiles(
  p_shard SMALLINT DEFAULT NULL,
  p_game_day BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_game_day BIGINT;
  v_count BIGINT;
BEGIN
  IF p_shard IS NOT NULL AND (p_shard < 0 OR p_shard > 63) THEN
    RAISE EXCEPTION 'Settlement profile shard must be between 0 and 63';
  END IF;
  SELECT COALESCE(p_game_day, (SELECT game_day FROM earth_get_current_game_time() LIMIT 1), 1)
  INTO v_game_day;

  WITH building_effects AS (
    SELECT p.owner_economic_id,
      SUM(e.output_units * e.effective_output_multiplier - (e.upkeep_units + e.operating_units) * e.effective_cost_multiplier) FILTER (WHERE e.asset_code = 'MATERIAL') AS materials,
      SUM(e.output_units * e.effective_output_multiplier - (e.upkeep_units + e.operating_units) * e.effective_cost_multiplier) FILTER (WHERE e.asset_code = 'COMPONENTS') AS components,
      SUM(e.output_units * e.effective_output_multiplier - (e.upkeep_units + e.operating_units) * e.effective_cost_multiplier) FILTER (WHERE e.asset_code = 'ENERGY') AS energy,
      SUM(e.output_units * e.effective_output_multiplier - (e.upkeep_units + e.operating_units) * e.effective_cost_multiplier) FILTER (WHERE e.asset_code = 'COMPUTE') AS compute,
      SUM(e.output_units * e.effective_output_multiplier - (e.upkeep_units + e.operating_units) * e.effective_cost_multiplier) FILTER (WHERE e.asset_code = 'FOOD') AS food
    FROM daily_settlement_profiles p
    JOIN buildings b ON (
      (p.owner_kind = 'city' AND b.city_id = p.owner_id AND b.ownership_class = 'civic')
      OR (p.owner_kind <> 'city' AND b.owner_id = p.owner_id AND b.ownership_class = 'private')
    )
    CROSS JOIN LATERAL earth_calculate_building_economics(b.id) e
    WHERE b.status = 'active'
      AND p.status = 'dirty'
      AND (p_shard IS NULL OR p.shard = p_shard)
    GROUP BY p.owner_economic_id
  ), updated AS (
    UPDATE daily_settlement_profiles p
    SET status = 'clean',
        profile_version = p.profile_version + 1,
        credit_units = 0,
        material_units = ROUND(COALESCE(e.materials, 0) * 1000000)::BIGINT,
        components_units = ROUND(COALESCE(e.components, 0) * 1000000)::BIGINT,
        energy_units = ROUND(COALESCE(e.energy, 0) * 1000000)::BIGINT,
        compute_units = ROUND(COALESCE(e.compute, 0) * 1000000)::BIGINT,
        food_units = ROUND(COALESCE(e.food, 0) * 1000000)::BIGINT,
        fingerprint = md5(concat_ws(':', p.owner_economic_id, v_game_day, COALESCE(e.materials, 0), COALESCE(e.components, 0), COALESCE(e.energy, 0), COALESCE(e.compute, 0), COALESCE(e.food, 0))),
        dirty_reason = NULL,
        effective_from_game_day = v_game_day,
        energy_delta = ROUND(COALESCE(e.energy, 0), 6),
        food_delta = ROUND(COALESCE(e.food, 0), 6),
        materials_delta = ROUND(COALESCE(e.materials, 0), 6),
        components_delta = ROUND(COALESCE(e.components, 0), 6),
        compute_delta = ROUND(COALESCE(e.compute, 0), 6),
        updated_at = CURRENT_TIMESTAMP
    FROM building_effects e
    WHERE p.owner_economic_id = e.owner_economic_id
    RETURNING p.owner_economic_id
  )
  SELECT COUNT(*) INTO v_count FROM updated;

  UPDATE daily_settlement_profiles p
  SET status = 'clean', profile_version = p.profile_version + 1,
      credit_units = 0, material_units = 0, components_units = 0,
      energy_units = 0, compute_units = 0, food_units = 0,
      fingerprint = md5(concat_ws(':', p.owner_economic_id, v_game_day, 'zero')),
      dirty_reason = NULL, effective_from_game_day = v_game_day,
      energy_delta = 0, food_delta = 0, materials_delta = 0,
      components_delta = 0, compute_delta = 0,
      updated_at = CURRENT_TIMESTAMP
  WHERE p.status = 'dirty'
    AND (p_shard IS NULL OR p.shard = p_shard);
  v_count := v_count + ROW_COUNT;
  RETURN v_count;
END;
$$;
