-- Technology & Research V2 Plan 20: patents expire into permanent public domain.

CREATE TABLE IF NOT EXISTS technology_public_domain (
  technology_id TEXT PRIMARY KEY REFERENCES technology_catalog(id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  source_patent_id TEXT NOT NULL REFERENCES technology_patents(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS technology_public_domain_effective_idx
  ON technology_public_domain (effective_from_game_day, technology_id);

CREATE OR REPLACE FUNCTION earth_finalize_technology_public_domain(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Public-domain game day must be non-negative';
  END IF;

  UPDATE technology_patents
  SET status = 'EXPIRED'
  WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;

  INSERT INTO technology_public_domain (technology_id, effective_from_game_day, source_patent_id)
  SELECT p.technology_id, p.exclusive_through_game_day + 1, p.id
  FROM technology_patents p
  WHERE p.status = 'EXPIRED'
    AND p.exclusive_through_game_day < p_game_day
  ON CONFLICT (technology_id) DO NOTHING;

  -- Materialize implicit public-domain access for the cache and audit paths.
  INSERT INTO corporation_technology_access (
    corporation_economic_id, technology_id, access_source, source_id,
    effective_from_game_day, status
  )
  SELECT o.economic_id, d.technology_id, 'GRANTED', 'PUBLIC_DOMAIN:' || d.technology_id,
    d.effective_from_game_day, 'ACTIVE'
  FROM owner_registry o
  CROSS JOIN technology_public_domain d
  WHERE o.owner_type ILIKE 'corporation'
    AND d.effective_from_game_day <= p_game_day
  ON CONFLICT (corporation_economic_id, technology_id, access_source, source_id)
  DO UPDATE SET status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_corporation_has_technology_access(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_game_day BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM corporation_technology_access a
    WHERE a.corporation_economic_id = p_corporation_economic_id
      AND a.technology_id = p_technology_id
      AND a.status = 'ACTIVE'
      AND a.effective_from_game_day <= p_game_day
      AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
  ) OR EXISTS (
    SELECT 1
    FROM technology_public_domain d
    WHERE d.technology_id = p_technology_id
      AND d.effective_from_game_day <= p_game_day
  );
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
    AND NOT EXISTS (
      SELECT 1 FROM technology_public_domain d WHERE d.technology_id = p.target_id
    )
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE technology_public_domain IS
  'Permanent public-domain status begins on the game day after patent exclusivity ends.';
