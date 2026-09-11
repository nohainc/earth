-- Technology & Research V2 Plan 7: one active research project per corporation.

WITH ranked_active AS (
  SELECT id,
    ROW_NUMBER() OVER (
      PARTITION BY corporation_economic_id
      ORDER BY priority DESC, created_at, id
    ) AS project_rank
  FROM corporation_research_projects
  WHERE status = 'ACTIVE'
)
UPDATE corporation_research_projects p
SET status = 'QUEUED', updated_at = CURRENT_TIMESTAMP
FROM ranked_active r
WHERE p.id = r.id AND r.project_rank > 1;

CREATE UNIQUE INDEX IF NOT EXISTS corporation_research_one_active_idx
  ON corporation_research_projects (corporation_economic_id)
  WHERE status = 'ACTIVE';

COMMENT ON INDEX corporation_research_one_active_idx IS
  'V1 research allocation allows one active project per corporation; additional projects remain queued.';
