-- Separate Initiative funding from execution. Funding pays into escrow; execution
-- has its own duration, resource requirements, progress model and completion state.

ALTER TABLE initiative_executions
  ADD COLUMN IF NOT EXISTS required_duration_game_days BIGINT,
  ADD COLUMN IF NOT EXISTS required_resource_requirements JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS consumed_resource_requirements JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS progress_model TEXT NOT NULL DEFAULT 'FUNDING_ONLY',
  ADD COLUMN IF NOT EXISTS blocked_reason TEXT;

ALTER TABLE initiative_executions DROP CONSTRAINT IF EXISTS initiative_executions_status_check;
ALTER TABLE initiative_executions ADD CONSTRAINT initiative_executions_status_check
  CHECK (status IN ('PENDING','ACTIVE','WAITING_RESOURCES','COMPLETED','FAILED','CANCELLED'));
ALTER TABLE initiative_executions DROP CONSTRAINT IF EXISTS initiative_executions_progress_model_check;
ALTER TABLE initiative_executions ADD CONSTRAINT initiative_executions_progress_model_check
  CHECK (progress_model IN ('FUNDING_ONLY','TIME','TIME_AND_RESOURCES'));
ALTER TABLE initiative_executions DROP CONSTRAINT IF EXISTS initiative_executions_duration_check;
ALTER TABLE initiative_executions ADD CONSTRAINT initiative_executions_duration_check
  CHECK ((progress_model = 'FUNDING_ONLY' AND required_duration_game_days IS NULL)
      OR (progress_model IN ('TIME','TIME_AND_RESOURCES') AND required_duration_game_days > 0));
ALTER TABLE initiative_executions DROP CONSTRAINT IF EXISTS initiative_executions_resource_requirements_check;
ALTER TABLE initiative_executions ADD CONSTRAINT initiative_executions_resource_requirements_check
  CHECK (jsonb_typeof(required_resource_requirements) = 'object' AND jsonb_typeof(consumed_resource_requirements) = 'object');

-- Backfill the execution leg for migrated canonical initiatives. These rows do
-- not inherit progress from historical money spent: programs receive a fresh
-- time-based execution leg and public projects remain funding-settlement based.
INSERT INTO initiative_executions
  (id, initiative_id, execution_model, status, progress_bps, required_duration_game_days,
   required_resource_requirements, progress_model, correlation_id)
SELECT 'INIT-EXECUTION-' || i.id, i.id, i.execution_model,
       CASE WHEN i.status = 'COMPLETED' THEN 'COMPLETED'
            WHEN i.status IN ('FAILED','CANCELLED') THEN i.status
            ELSE 'PENDING' END,
       CASE WHEN i.status = 'COMPLETED' THEN 10000 ELSE 0 END,
       CASE WHEN i.initiative_type = 'PROGRAM' THEN 30 ELSE NULL END,
       '{}'::JSONB,
       CASE WHEN i.initiative_type = 'PROGRAM' THEN 'TIME' ELSE 'FUNDING_ONLY' END,
       'initiative-execution:migration:' || i.id
  FROM v5_initiatives i
 WHERE NOT EXISTS (SELECT 1 FROM initiative_executions e WHERE e.initiative_id = i.id)
ON CONFLICT (initiative_id) DO NOTHING;

-- Existing migrated records retain their historical lifecycle while receiving an
-- explicit model. Legacy Programs execute over time; Projects settle at funding.
UPDATE initiative_executions e
   SET progress_model = CASE WHEN i.initiative_type = 'PROGRAM' THEN 'TIME' ELSE 'FUNDING_ONLY' END,
       required_duration_game_days = CASE WHEN i.initiative_type = 'PROGRAM' THEN 30 ELSE NULL END
  FROM v5_initiatives i
 WHERE i.id = e.initiative_id
   AND e.progress_model = 'FUNDING_ONLY'
   AND (i.initiative_type = 'PROGRAM' OR e.execution_model IN ('FUNDING_ONLY','PUBLIC_WORK'));
