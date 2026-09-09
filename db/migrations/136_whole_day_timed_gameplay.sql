-- Clean whole-day calendar for all timed gameplay. Runtime code must use only
-- these fields; retained minute fields are historical audit data only.

ALTER TABLE scheduled_actions
  ADD COLUMN IF NOT EXISTS due_end_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
UPDATE scheduled_actions SET due_end_game_day = due_game_day WHERE due_end_game_day IS NULL;
ALTER TABLE scheduled_actions ALTER COLUMN due_end_game_day SET NOT NULL;
CREATE INDEX IF NOT EXISTS scheduled_actions_end_of_day_idx
  ON scheduled_actions (status, due_end_game_day, priority, created_at);

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS construction_start_day BIGINT,
  ADD COLUMN IF NOT EXISTS construction_duration_days INTEGER,
  ADD COLUMN IF NOT EXISTS construction_due_end_day BIGINT,
  ADD COLUMN IF NOT EXISTS construction_completed_day BIGINT;
UPDATE buildings
SET construction_start_day = COALESCE(construction_started_game_day, created_game_day, 1),
    construction_duration_days = GREATEST(1, COALESCE(construction_complete_game_day, construction_started_game_day + 1) - COALESCE(construction_started_game_day, created_game_day, 1) + 1),
    construction_due_end_day = COALESCE(construction_complete_game_day, construction_started_game_day, created_game_day, 1)
WHERE construction_start_day IS NULL;
ALTER TABLE buildings ALTER COLUMN construction_start_day SET NOT NULL;
ALTER TABLE buildings ALTER COLUMN construction_duration_days SET NOT NULL;
ALTER TABLE buildings ALTER COLUMN construction_due_end_day SET NOT NULL;
CREATE INDEX IF NOT EXISTS buildings_construction_due_end_idx ON buildings(status, construction_due_end_day);

ALTER TABLE corporation_building_research_projects
  ADD COLUMN IF NOT EXISTS research_start_day BIGINT,
  ADD COLUMN IF NOT EXISTS research_duration_days INTEGER,
  ADD COLUMN IF NOT EXISTS research_due_end_day BIGINT,
  ADD COLUMN IF NOT EXISTS research_completed_day BIGINT;
UPDATE corporation_building_research_projects
SET research_start_day = COALESCE(started_game_day, 1),
    research_duration_days = GREATEST(1, CEIL(COALESCE(duration_minutes, 1440)::numeric / 1440.0)::integer),
    research_due_end_day = COALESCE(started_game_day, 1) + GREATEST(1, CEIL(COALESCE(duration_minutes, 1440)::numeric / 1440.0)::integer) - 1,
    research_completed_day = completed_game_day
WHERE research_start_day IS NULL;
ALTER TABLE corporation_building_research_projects ALTER COLUMN research_start_day SET NOT NULL;
ALTER TABLE corporation_building_research_projects ALTER COLUMN research_duration_days SET NOT NULL;
ALTER TABLE corporation_building_research_projects ALTER COLUMN research_due_end_day SET NOT NULL;
CREATE INDEX IF NOT EXISTS corp_building_research_due_end_idx ON corporation_building_research_projects(status, research_due_end_day);

ALTER TABLE corporation_technology_projects
  ADD COLUMN IF NOT EXISTS research_start_day BIGINT,
  ADD COLUMN IF NOT EXISTS research_duration_days INTEGER,
  ADD COLUMN IF NOT EXISTS research_due_end_day BIGINT;
UPDATE corporation_technology_projects
SET research_start_day = COALESCE(started_game_day, 1),
    research_duration_days = 1,
    research_due_end_day = COALESCE(completed_game_day, started_game_day, 1)
WHERE research_start_day IS NULL;
ALTER TABLE corporation_technology_projects ALTER COLUMN research_start_day SET NOT NULL;
ALTER TABLE corporation_technology_projects ALTER COLUMN research_duration_days SET NOT NULL;
ALTER TABLE corporation_technology_projects ALTER COLUMN research_due_end_day SET NOT NULL;

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS submitted_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS voting_start_day BIGINT,
  ADD COLUMN IF NOT EXISTS voting_duration_days INTEGER,
  ADD COLUMN IF NOT EXISTS voting_due_end_day BIGINT,
  ADD COLUMN IF NOT EXISTS resolved_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS implementation_due_end_day BIGINT,
  ADD COLUMN IF NOT EXISTS executed_game_day BIGINT;
UPDATE proposals
SET submitted_game_day = COALESCE(opens_game_day, closes_game_day, 1),
    voting_start_day = COALESCE(opens_game_day, closes_game_day, 1),
    voting_duration_days = GREATEST(1, COALESCE(closes_game_day, opens_game_day, 1) - COALESCE(opens_game_day, closes_game_day, 1) + 1),
    voting_due_end_day = COALESCE(closes_game_day, opens_game_day, 1),
    resolved_game_day = CASE WHEN resolved_at IS NOT NULL THEN COALESCE(closes_game_day, opens_game_day, 1) END,
    implementation_due_end_day = implementation_game_day,
    executed_game_day = CASE WHEN executed_at IS NOT NULL THEN COALESCE(implementation_game_day, closes_game_day, opens_game_day, 1) END
WHERE submitted_game_day IS NULL;
ALTER TABLE proposals ALTER COLUMN submitted_game_day SET NOT NULL;
ALTER TABLE proposals ALTER COLUMN voting_start_day SET NOT NULL;
ALTER TABLE proposals ALTER COLUMN voting_duration_days SET NOT NULL;
ALTER TABLE proposals ALTER COLUMN voting_due_end_day SET NOT NULL;
CREATE INDEX IF NOT EXISTS proposals_whole_day_voting_idx ON proposals(status, voting_start_day, voting_due_end_day);
CREATE INDEX IF NOT EXISTS proposals_whole_day_execution_idx ON proposals(execution_status, implementation_due_end_day);
