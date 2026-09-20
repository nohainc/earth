ALTER TABLE humans
  ADD COLUMN IF NOT EXISTS epitaph TEXT;

CREATE TABLE IF NOT EXISTS human_memorial_records (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  generation INTEGER NOT NULL CHECK (generation > 0),
  display_name TEXT NOT NULL,
  birth_game_day BIGINT NOT NULL,
  death_game_day BIGINT NOT NULL,
  age_years INTEGER NOT NULL CHECK (age_years >= 0),
  final_standing BIGINT NOT NULL CHECK (final_standing >= 0),
  final_legacy BIGINT NOT NULL CHECK (final_legacy >= 0),
  cause_code TEXT NOT NULL CHECK (cause_code IN (
    'NATURAL_AGE',
    'ESSENTIAL_NEEDS_DEPRIVATION',
    'HEALTH_SERVICE_DEPRIVATION',
    'SYSTEM_ADMINISTRATIVE'
  )),
  cause_details JSONB NOT NULL DEFAULT '{}'::JSONB,
  corporation_id TEXT,
  corporation_name TEXT,
  successor_human_id TEXT,
  successor_name TEXT,
  final_house_economic_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  epitaph TEXT,
  record_version TEXT NOT NULL DEFAULT 'human-memorial-v1',
  created_game_day BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS human_memorial_records_house_idx
  ON human_memorial_records (house_id, generation, death_game_day);

CREATE OR REPLACE FUNCTION earth_reject_memorial_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'human memorial records are immutable';
END;
$$;

DROP TRIGGER IF EXISTS human_memorial_records_immutable ON human_memorial_records;
CREATE TRIGGER human_memorial_records_immutable
  BEFORE UPDATE OR DELETE ON human_memorial_records
  FOR EACH ROW EXECUTE FUNCTION earth_reject_memorial_mutation();
