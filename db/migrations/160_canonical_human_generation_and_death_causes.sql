ALTER TABLE humans
  ADD COLUMN IF NOT EXISTS generation INTEGER NOT NULL DEFAULT 1
  CHECK (generation > 0);

ALTER TABLE human_memorial_records
  ADD COLUMN IF NOT EXISTS generation_source TEXT NOT NULL DEFAULT 'SUCCESSION_HISTORY_V1',
  ADD COLUMN IF NOT EXISTS cause_classification_version TEXT NOT NULL DEFAULT 'mortality-cause-v1';

ALTER TABLE human_memorial_records
  DROP CONSTRAINT IF EXISTS human_memorial_records_cause_code_check;

ALTER TABLE human_memorial_records
  ADD CONSTRAINT human_memorial_records_cause_code_check
  CHECK (cause_code IN (
    'NATURAL_AGE',
    'ESSENTIAL_NEEDS_DEPRIVATION',
    'HEALTH_SERVICE_DEPRIVATION',
    'SYSTEM_ADMINISTRATIVE'
  ));
