-- Technology & Research V2 Plan 40: deterministic same-day patent races.
-- A patent winner must not depend on PostgreSQL scan or insert order.

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

  -- Serialize the catalog rows so a research-start check and this grant
  -- decision cannot observe an ambiguous half-completed race.
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
  SELECT 'PATENT-' || w.target_id || '-' || w.id,
    w.target_id, w.corporation_economic_id, w.completed_game_day,
    w.completed_game_day + GREATEST(0, w.patent_exclusivity_days) - 1,
    'ACTIVE', w.id
  FROM (
    SELECT DISTINCT ON (p.target_id)
      p.id,
      p.target_id,
      p.corporation_economic_id,
      p.completed_game_day,
      t.patent_exclusivity_days
    FROM corporation_research_projects p
    JOIN technology_catalog t ON t.id = p.target_id
    WHERE p.target_type = 'TECHNOLOGY'
      AND p.status = 'COMPLETED'
      AND p.completed_game_day = p_game_day
      AND t.patentable
      AND t.status = 'ACTIVE'
      AND t.patent_exclusivity_days > 0
    -- Lower economic owner id wins; project id is a stable tie-breaker.
    ORDER BY p.target_id, p.corporation_economic_id, p.id
  ) AS w
  WHERE NOT EXISTS (
    SELECT 1
    FROM technology_public_domain d
    WHERE d.technology_id = w.target_id
  )
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION earth_grant_completed_technology_patents(BIGINT) IS
  'Grants one deterministic patent winner per technology for same-day completions; lower owner id wins.';
