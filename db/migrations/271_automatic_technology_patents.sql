-- Technology & Research V2 Plan 18: automatically grant the first patent
-- discovered by a corporation for a patentable technology.

CREATE TABLE IF NOT EXISTS technology_patents (
  id TEXT PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  granted_game_day BIGINT NOT NULL CHECK (granted_game_day >= 0),
  exclusive_through_game_day BIGINT NOT NULL CHECK (exclusive_through_game_day >= granted_game_day),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXPIRED', 'REVOKED')),
  granting_project_id TEXT NOT NULL REFERENCES corporation_research_projects(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS technology_patents_one_active_idx
  ON technology_patents (technology_id)
  WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS technology_patents_owner_idx
  ON technology_patents (owner_economic_id, status);

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

COMMENT ON TABLE technology_patents IS
  'Corporation-owned patents automatically granted on first qualifying V2 technology discovery.';
