-- Technology & Research V2 Plan 19: grandfather already-started research,
-- but block new independent research during patent exclusivity.

CREATE OR REPLACE FUNCTION earth_assert_technology_research_allowed(
  p_technology_id TEXT,
  p_effective_game_day BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_effective_game_day < 0 THEN
    RAISE EXCEPTION 'Research effective game day must be non-negative';
  END IF;

  -- Serialize this decision with patent creation for the same catalog row.
  PERFORM 1 FROM technology_catalog WHERE id = p_technology_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown technology %', p_technology_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM technology_patents
    WHERE technology_id = p_technology_id
      AND status = 'ACTIVE'
      AND granted_game_day <= p_effective_game_day
      AND exclusive_through_game_day >= p_effective_game_day
  ) THEN
    RAISE EXCEPTION 'Technology % is under patent exclusivity through game day %',
      p_technology_id,
      (SELECT exclusive_through_game_day FROM technology_patents
       WHERE technology_id = p_technology_id AND status = 'ACTIVE'
       ORDER BY exclusive_through_game_day DESC LIMIT 1);
  END IF;
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

  UPDATE technology_patents
  SET status = 'EXPIRED'
  WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;

  -- Lock catalog definitions before checking/inserting patents. A concurrent
  -- research-start check therefore sees either the patent or the pre-patent
  -- state, never an ambiguous intermediate decision.
  PERFORM t.id
  FROM technology_catalog t
  JOIN corporation_research_projects p ON p.target_id = t.id
  WHERE p.target_type = 'TECHNOLOGY'
    AND p.status = 'COMPLETED'
    AND p.completed_game_day = p_game_day
    AND t.patentable
  FOR UPDATE;

  INSERT INTO technology_patents (
    id, technology_id, owner_economic_id, granted_game_day,
    exclusive_through_game_day, status, granting_project_id
  )
  SELECT 'PATENT-' || p.target_id || '-' || p.id,
    p.target_id, p.corporation_economic_id, p.completed_game_day,
    p.completed_game_day + GREATEST(0, t.patent_exclusivity_days) - 1,
    'ACTIVE', p.id
  FROM corporation_research_projects p
  JOIN technology_catalog t ON t.id = p.target_id
  WHERE p.target_type = 'TECHNOLOGY'
    AND p.status = 'COMPLETED'
    AND p.completed_game_day = p_game_day
    AND t.patentable
    AND t.status = 'ACTIVE'
    AND t.patent_exclusivity_days > 0
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION earth_assert_technology_research_allowed(TEXT, BIGINT) IS
  'Blocks new research during patent exclusivity while allowing already-started projects to finish.';
