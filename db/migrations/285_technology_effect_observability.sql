-- Technology & Research V2 Plan 33: explainable technology effects.

ALTER TABLE corporation_technology_modifier_cache
  ADD COLUMN IF NOT EXISTS technology_source_breakdown JSONB NOT NULL DEFAULT '[]'::JSONB;
ALTER TABLE building_settlement_journals
  ADD COLUMN IF NOT EXISTS technology_effects JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE OR REPLACE FUNCTION earth_refresh_technology_modifier_sources(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE corporation_technology_modifier_cache cache
  SET technology_source_breakdown = COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'technologyId', technology.id,
      'technologyCode', technology.code,
      'technologyName', technology.name,
      'effectType', effect.effect_type,
      'modifierFamily', effect.modifier_family,
      'targetType', effect.target_type,
      'targetKey', effect.target_key,
      'modifierBps', effect.modifier_bps
    ) ORDER BY technology.code, effect.effect_type, effect.target_key)
    FROM corporation_technology_access access
    JOIN technology_effects effect ON effect.technology_id = access.technology_id
    JOIN technology_catalog technology ON technology.id = effect.technology_id
    WHERE access.corporation_economic_id = cache.corporation_economic_id
      AND access.status = 'ACTIVE'
      AND access.effective_from_game_day <= p_game_day
      AND (access.effective_to_game_day IS NULL OR access.effective_to_game_day >= p_game_day)
      AND technology.status = 'ACTIVE'
      AND technology.effective_from_game_day <= p_game_day
      AND (technology.effective_to_game_day IS NULL OR technology.effective_to_game_day >= p_game_day)
  ), '[]'::JSONB)
  WHERE cache.game_day = p_game_day;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN building_settlement_journals.technology_effects IS
  'Explainable technology source/effect breakdown used by Building V2 for this settlement day.';
