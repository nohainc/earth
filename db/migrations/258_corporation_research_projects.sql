-- Technology & Research V2 Plan 4: one corporation research project model.

CREATE TABLE IF NOT EXISTS corporation_research_projects (
  id TEXT PRIMARY KEY,
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  target_type TEXT NOT NULL CHECK (target_type IN ('TECHNOLOGY', 'BUILDING_BLUEPRINT')),
  target_id TEXT NOT NULL,
  definition_version TEXT NOT NULL,
  required_research_points BIGINT NOT NULL CHECK (required_research_points > 0),
  progress_research_points BIGINT NOT NULL DEFAULT 0 CHECK (progress_research_points >= 0),
  credit_cost_units BIGINT NOT NULL CHECK (credit_cost_units >= 0),
  priority INTEGER NOT NULL DEFAULT 100 CHECK (priority BETWEEN 0 AND 1000),
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'ACTIVE', 'COMPLETED', 'CANCELLED')),
  started_game_day BIGINT,
  completed_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (progress_research_points <= required_research_points),
  CHECK (completed_game_day IS NULL OR started_game_day IS NULL OR completed_game_day >= started_game_day)
);

CREATE INDEX IF NOT EXISTS corporation_research_projects_queue_idx
  ON corporation_research_projects (corporation_economic_id, status, priority DESC, created_at, id);
CREATE UNIQUE INDEX IF NOT EXISTS corporation_research_projects_active_target_idx
  ON corporation_research_projects (corporation_economic_id, target_type, target_id)
  WHERE status IN ('QUEUED', 'ACTIVE', 'COMPLETED');

INSERT INTO corporation_research_projects (
  id, corporation_economic_id, target_type, target_id, definition_version,
  required_research_points, progress_research_points, credit_cost_units,
  priority, status, started_game_day, completed_game_day, correlation_id,
  created_at, updated_at
)
SELECT p.id, owner.economic_id, 'TECHNOLOGY', p.technology_key, 'legacy-corporation-technology-v1',
  100, ROUND(GREATEST(0, LEAST(100, p.progress)))::BIGINT,
  ROUND(GREATEST(0, p.research_cost_credits) * 100)::BIGINT, 100,
  CASE p.status WHEN 'active' THEN 'ACTIVE' WHEN 'completed' THEN 'COMPLETED' ELSE 'CANCELLED' END,
  p.started_game_day, p.completed_game_day, COALESCE(p.correlation_id, 'legacy-technology:' || p.id),
  p.created_at, p.updated_at
FROM corporation_technology_projects p
JOIN owner_registry owner ON owner.id = p.corporation_id
ON CONFLICT (id) DO NOTHING;

INSERT INTO corporation_research_projects (
  id, corporation_economic_id, target_type, target_id, definition_version,
  required_research_points, progress_research_points, credit_cost_units,
  priority, status, started_game_day, completed_game_day, correlation_id,
  created_at, updated_at
)
SELECT p.id, owner.economic_id, 'BUILDING_BLUEPRINT', p.catalog_id, 'legacy-building-blueprint-v1',
  GREATEST(1, p.research_duration_days * 100),
  ROUND(GREATEST(0, LEAST(100, p.progress)) * GREATEST(1, p.research_duration_days))::BIGINT,
  ROUND(GREATEST(0, p.research_cost_credits) * 100)::BIGINT, 100,
  CASE p.status WHEN 'active' THEN 'ACTIVE' WHEN 'completed' THEN 'COMPLETED' ELSE 'CANCELLED' END,
  p.started_game_day, p.completed_game_day, COALESCE(p.correlation_id, 'legacy-building:' || p.id),
  p.created_at, p.updated_at
FROM corporation_building_research_projects p
JOIN owner_registry owner ON owner.id = p.corporation_id
ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE corporation_research_projects IS
  'Unified corporation research queue for technology and building blueprint targets.';
