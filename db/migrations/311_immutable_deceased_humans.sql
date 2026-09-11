-- Death & Continuity V2 Plan 28.
-- A deceased Human is an historical record, never mutable gameplay state.

ALTER TABLE deceased_profiles
  ADD COLUMN IF NOT EXISTS final_age_years INTEGER,
  ADD COLUMN IF NOT EXISTS corporation_id TEXT,
  ADD COLUMN IF NOT EXISTS city_id TEXT,
  ADD COLUMN IF NOT EXISTS major_titles JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS achievements JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN deceased_profiles.major_titles IS
  'Immutable historical snapshot of major offices/titles held at death.';
COMMENT ON COLUMN deceased_profiles.achievements IS
  'Immutable historical snapshot of important achievements known at death.';

CREATE OR REPLACE FUNCTION earth_prevent_deceased_human_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.life_status = 'deceased' OR OLD.mortality_state = 'DECEASED' THEN
    RAISE EXCEPTION 'Deceased Human % is immutable historical data', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS humans_deceased_immutability_trigger ON humans;
CREATE TRIGGER humans_deceased_immutability_trigger
  BEFORE UPDATE ON humans
  FOR EACH ROW EXECUTE FUNCTION earth_prevent_deceased_human_mutation();

-- Backfill the age snapshot for existing historical profiles where possible.
UPDATE deceased_profiles profile
SET final_age_years = human.age_years
FROM humans human
WHERE profile.human_id = human.id
  AND profile.final_age_years IS NULL;
