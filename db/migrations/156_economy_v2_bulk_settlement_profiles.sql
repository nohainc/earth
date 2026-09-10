-- Economy V2 Plan 7: compact, bulk-rebuilt settlement profiles.
-- Legacy profile columns remain as a compatibility bridge until the scheduler
-- and settlement posting path no longer read them.

ALTER TABLE daily_settlement_profiles
  ADD COLUMN IF NOT EXISTS owner_economic_id BIGINT,
  ADD COLUMN IF NOT EXISTS shard SMALLINT,
  ADD COLUMN IF NOT EXISTS credit_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS material_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS components_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS energy_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS compute_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS food_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fingerprint TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS dirty_reason TEXT,
  ADD COLUMN IF NOT EXISTS effective_from_game_day BIGINT;

UPDATE daily_settlement_profiles p
SET owner_economic_id = o.economic_id,
    shard = mod(abs(hashtextextended(p.owner_id, 0)), 64)::SMALLINT,
    effective_from_game_day = COALESCE(p.effective_from_game_day, p.effective_game_day)
FROM owner_registry o
WHERE o.id = p.owner_id
  AND (p.owner_economic_id IS NULL OR p.shard IS NULL OR p.effective_from_game_day IS NULL);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM daily_settlement_profiles WHERE owner_economic_id IS NULL) THEN
    RAISE EXCEPTION 'Cannot assign economic IDs to all settlement profiles';
  END IF;
END;
$$;

ALTER TABLE daily_settlement_profiles
  ALTER COLUMN owner_economic_id SET NOT NULL,
  ALTER COLUMN shard SET NOT NULL,
  ALTER COLUMN effective_from_game_day SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS daily_settlement_profiles_economic_owner_uq
  ON daily_settlement_profiles (owner_economic_id);
CREATE INDEX IF NOT EXISTS daily_settlement_profiles_v2_dirty_shard_idx
  ON daily_settlement_profiles (status, shard, owner_economic_id)
  WHERE status = 'dirty';

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
           SUM((COALESCE(bc.output_materials, 0) - COALESCE(bc.upkeep_materials, 0) - COALESCE(bc.operating_materials, 0)) * CASE WHEN b.operating_policy = 'high_output' THEN 1.3 WHEN b.operating_policy IN ('frugal', 'eco_reserve') THEN 0.75 WHEN b.operating_policy = 'halted' THEN 0.0 ELSE 1.0 END)::NUMERIC AS materials,
           SUM((COALESCE(bc.output_components, 0) - COALESCE(bc.upkeep_components, 0) - COALESCE(bc.operating_components, 0)) * CASE WHEN b.operating_policy = 'high_output' THEN 1.3 WHEN b.operating_policy IN ('frugal', 'eco_reserve') THEN 0.75 WHEN b.operating_policy = 'halted' THEN 0.0 ELSE 1.0 END)::NUMERIC AS components,
           SUM((COALESCE(bc.output_energy, 0) - COALESCE(bc.upkeep_energy, 0) - COALESCE(bc.operating_energy, 0)) * CASE WHEN b.operating_policy = 'high_output' THEN 1.3 WHEN b.operating_policy IN ('frugal', 'eco_reserve') THEN 0.75 WHEN b.operating_policy = 'halted' THEN 0.0 ELSE 1.0 END)::NUMERIC AS energy,
           SUM((COALESCE(bc.output_compute, 0) - COALESCE(bc.upkeep_compute, 0) - COALESCE(bc.operating_compute, 0)) * CASE WHEN b.operating_policy = 'high_output' THEN 1.3 WHEN b.operating_policy IN ('frugal', 'eco_reserve') THEN 0.75 WHEN b.operating_policy = 'halted' THEN 0.0 ELSE 1.0 END)::NUMERIC AS compute,
           SUM((COALESCE(bc.output_food, 0) - COALESCE(bc.upkeep_food, 0) - COALESCE(bc.operating_food, 0)) * CASE WHEN b.operating_policy = 'high_output' THEN 1.3 WHEN b.operating_policy IN ('frugal', 'eco_reserve') THEN 0.75 WHEN b.operating_policy = 'halted' THEN 0.0 ELSE 1.0 END)::NUMERIC AS food
    FROM daily_settlement_profiles p
    JOIN buildings b ON (
      (p.owner_kind = 'city' AND b.city_id = p.owner_id AND b.ownership_class = 'civic')
      OR (p.owner_kind <> 'city' AND b.owner_id = p.owner_id AND b.ownership_class = 'private')
    )
    JOIN building_catalog bc ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
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
        -- Compatibility projection for pre-V2 readers.
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

  -- Profiles with no active buildings still become clean with zero effects.
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
