-- Technology & Research V2 Plan 37: one capacity-driven research settlement.
-- Research completed while settling Day N is deliberately effective on Day N + 1.

CREATE OR REPLACE FUNCTION earth_sync_corporation_researched_technology_access(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Technology access game day must be non-negative';
  END IF;

  INSERT INTO corporation_technology_access (
    corporation_economic_id, technology_id, access_source, source_id,
    effective_from_game_day, status
  )
  SELECT p.corporation_economic_id, p.target_id, 'RESEARCHED', p.id,
    p.completed_game_day + 1, 'ACTIVE'
  FROM corporation_research_projects p
  WHERE p.target_type = 'TECHNOLOGY'
    AND p.status = 'COMPLETED'
    AND p.completed_game_day IS NOT NULL
  ON CONFLICT (corporation_economic_id, technology_id, access_source, source_id)
  DO UPDATE SET effective_from_game_day = EXCLUDED.effective_from_game_day,
                status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_completed_technology_patents(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Patent grant game day must be non-negative';
  END IF;

  INSERT INTO technology_patents (
    id, technology_id, owner_economic_id, granted_game_day,
    exclusive_through_game_day, status, granting_project_id
  )
  SELECT 'PATENT-' || p.target_id || '-' || p.id,
    p.target_id, p.corporation_economic_id, p.completed_game_day + 1,
    p.completed_game_day + GREATEST(0, t.patent_exclusivity_days),
    'ACTIVE', p.id
  FROM corporation_research_projects p
  JOIN technology_catalog t ON t.id = p.target_id
  WHERE p.target_type = 'TECHNOLOGY'
    AND p.status = 'COMPLETED'
    AND p.completed_game_day = p_game_day
    AND t.patentable
    AND t.status = 'ACTIVE'
    AND t.patent_exclusivity_days > 0
    AND NOT EXISTS (
      SELECT 1 FROM technology_public_domain d WHERE d.technology_id = p.target_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM technology_patents existing
      WHERE existing.technology_id = p.target_id
        AND existing.status = 'ACTIVE'
    )
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_settle_research_and_progress_v2(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_completed BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Research settlement game day must be non-negative';
  END IF;

  -- Capacity is recorded from the already-settled Building V2 plans. The
  -- advance function selects one deterministic project per corporation and
  -- applies the day-effective technology modifier and priority.
  PERFORM earth_record_corporation_research_capacity(p_game_day);
  v_completed := earth_advance_corporation_research_v2(p_game_day);

  -- Completion side effects are kept in this same transaction and are
  -- explicitly next-day effective. Access triggers dirty the modifier cache.
  PERFORM earth_sync_corporation_researched_technology_access(p_game_day);
  PERFORM earth_grant_completed_technology_patents(p_game_day);

  INSERT INTO corporation_building_unlocks (
    corporation_id, catalog_id, research_project_id, unlocked_game_day
  )
  SELECT owner.source_id, p.target_id, NULL, p_game_day + 1
  FROM corporation_research_projects p
  JOIN owner_registry owner ON owner.economic_id = p.corporation_economic_id
   AND owner.owner_type ILIKE 'corporation'
  WHERE p.target_type = 'BUILDING_BLUEPRINT'
    AND p.status = 'COMPLETED'
    AND p.completed_game_day = p_game_day
  ON CONFLICT (corporation_id, catalog_id) DO UPDATE
    SET status = 'unlocked', unlocked_game_day = EXCLUDED.unlocked_game_day;

  INSERT INTO corporation_technology_modifier_invalidations (
    corporation_economic_id, effective_game_day, reason_code, source_id
  )
  SELECT p.corporation_economic_id, p_game_day + 1,
    'RESEARCH_COMPLETED', p.id
  FROM corporation_research_projects p
  WHERE p.status = 'COMPLETED'
    AND p.completed_game_day = p_game_day
  ON CONFLICT DO NOTHING;

  RETURN COALESCE(v_completed, 0);
END;
$$;

COMMENT ON FUNCTION earth_settle_research_and_progress_v2(BIGINT) IS
  'Advances one priority research project per corporation from settled capacity and applies all completion effects for the next game day.';
