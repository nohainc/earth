-- Technology & Research V2 Plan 35: shallow, normalized prerequisites.

CREATE TABLE IF NOT EXISTS technology_prerequisites (
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id) ON DELETE CASCADE,
  requires_technology_id TEXT NOT NULL REFERENCES technology_catalog(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (technology_id, requires_technology_id),
  CHECK (technology_id <> requires_technology_id)
);

CREATE INDEX IF NOT EXISTS technology_prerequisites_requires_idx
  ON technology_prerequisites (requires_technology_id, technology_id);

CREATE OR REPLACE FUNCTION earth_validate_technology_prerequisite_graph()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_depth INTEGER;
BEGIN
  IF EXISTS (
    WITH RECURSIVE walk(technology_id, depth) AS (
      SELECT NEW.requires_technology_id, 1
      UNION ALL
      SELECT p.requires_technology_id, walk.depth + 1
      FROM technology_prerequisites p JOIN walk ON p.technology_id = walk.technology_id
      WHERE walk.depth < 10
    )
    SELECT 1 FROM walk WHERE technology_id = NEW.technology_id
  ) THEN RAISE EXCEPTION 'Technology prerequisite cycle is not allowed'; END IF;

  WITH RECURSIVE walk(technology_id, depth) AS (
    SELECT NEW.requires_technology_id, 1
    UNION ALL
    SELECT p.requires_technology_id, walk.depth + 1
    FROM technology_prerequisites p JOIN walk ON p.technology_id = walk.technology_id
    WHERE walk.depth < 10
  )
  SELECT MAX(depth) INTO v_depth FROM walk;
  IF COALESCE(v_depth, 0) > 3 THEN RAISE EXCEPTION 'Technology prerequisite graph may not exceed three levels'; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS technology_prerequisite_graph_trigger ON technology_prerequisites;
CREATE TRIGGER technology_prerequisite_graph_trigger
  BEFORE INSERT OR UPDATE ON technology_prerequisites
  FOR EACH ROW EXECUTE FUNCTION earth_validate_technology_prerequisite_graph();

CREATE OR REPLACE FUNCTION earth_assert_technology_prerequisites_met(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_game_day BIGINT
)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_missing TEXT;
BEGIN
  SELECT p.requires_technology_id INTO v_missing
  FROM technology_prerequisites p
  WHERE p.technology_id = p_technology_id
    AND NOT earth_corporation_has_technology_access(
      p_corporation_economic_id, p.requires_technology_id, p_game_day
    )
  ORDER BY p.requires_technology_id
  LIMIT 1;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Technology % requires technology % first', p_technology_id, v_missing;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_validate_research_project_prerequisites()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.target_type = 'TECHNOLOGY' THEN
    PERFORM earth_assert_technology_prerequisites_met(
      NEW.corporation_economic_id, NEW.target_id, COALESCE(NEW.started_game_day, 0) + 1
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS corporation_research_prerequisites_trigger ON corporation_research_projects;
CREATE TRIGGER corporation_research_prerequisites_trigger
  BEFORE INSERT ON corporation_research_projects
  FOR EACH ROW EXECUTE FUNCTION earth_validate_research_project_prerequisites();

COMMENT ON TABLE technology_prerequisites IS
  'Normalized technology prerequisites; intentionally limited to a shallow three-level graph.';
