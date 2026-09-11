-- Building Economy V2 Plan 21: generic profiles exclude building economics.

ALTER TABLE daily_settlement_profiles
  ADD COLUMN IF NOT EXISTS includes_building_economics BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN daily_settlement_profiles.includes_building_economics IS
  'Must remain false: Building V2 is the sole owner of building production, upkeep, services, and repairs.';

-- Replace the former profile builder, which aggregated active building catalog
-- values. Generic profiles remain available for future non-building recurring
-- mechanics, but they cannot carry building-origin deltas.
CREATE OR REPLACE FUNCTION earth_rebuild_dirty_profiles(
  p_shard SMALLINT DEFAULT NULL,
  p_game_day BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_shard IS NOT NULL AND (p_shard < 0 OR p_shard > 63) THEN
    RAISE EXCEPTION 'Settlement profile shard must be between 0 and 63';
  END IF;

  UPDATE daily_settlement_profiles p
  SET includes_building_economics = FALSE,
      status = 'clean',
      profile_version = p.profile_version + 1,
      credit_units = 0,
      material_units = 0,
      components_units = 0,
      energy_units = 0,
      compute_units = 0,
      food_units = 0,
      credits_delta = 0,
      energy_delta = 0,
      food_delta = 0,
      materials_delta = 0,
      components_delta = 0,
      compute_delta = 0,
      fingerprint = md5(concat_ws(':', p.owner_economic_id, COALESCE(p_game_day, p.effective_game_day), 'non-building-profile-v2')),
      dirty_reason = NULL,
      effective_from_game_day = COALESCE(p_game_day, p.effective_game_day),
      updated_at = CURRENT_TIMESTAMP
  WHERE p.status = 'dirty'
    AND (p_shard IS NULL OR p.shard = p_shard);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_building_profile_overlap_integrity()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'building_profile_nonzero'::TEXT, COUNT(*)::BIGINT
  FROM daily_settlement_profiles p
  WHERE p.includes_building_economics
     OR p.credit_units <> 0
     OR p.material_units <> 0
     OR p.components_units <> 0
     OR p.energy_units <> 0
     OR p.compute_units <> 0
     OR p.food_units <> 0
  UNION ALL
  SELECT 'building_effect_posted_by_both_paths'::TEXT, COUNT(DISTINCT e.source_id)::BIGINT
  FROM settlement_effects e
  JOIN building_economic_batches b
    ON b.game_day = e.game_day AND b.status = 'POSTED'
  JOIN building_economic_effects be
    ON be.batch_id = b.id AND be.source_id = e.source_id
  WHERE e.phase = 'profile_settlement'
    AND EXISTS (SELECT 1 FROM buildings building WHERE building.id = e.source_id);
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT check_name, invalid_count FROM earth_base_integrity_report()
  UNION ALL SELECT check_name, invalid_count FROM earth_market_integrity_report()
  UNION ALL SELECT check_name, invalid_count FROM earth_monetary_supply_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_finance_v2_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_building_v2_integrity()
  UNION ALL SELECT check_name, invalid_count FROM earth_building_profile_overlap_integrity()
$$;
