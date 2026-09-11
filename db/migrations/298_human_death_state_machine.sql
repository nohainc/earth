-- Death, Inheritance & House Continuity V2 Plan 6.
-- Mortality is an explicit atomic state transition; House continuity remains
-- active throughout the transition.

ALTER TABLE humans
  ADD COLUMN IF NOT EXISTS mortality_state TEXT NOT NULL DEFAULT 'ACTIVE';

UPDATE humans
SET mortality_state = CASE
  WHEN life_status = 'deceased' THEN 'DECEASED'
  WHEN life_status = 'estate' THEN 'DEATH_CONFIRMED'
  ELSE 'ACTIVE'
END
WHERE mortality_state = 'ACTIVE' AND life_status <> 'active';

ALTER TABLE humans DROP CONSTRAINT IF EXISTS humans_mortality_state_ck;
ALTER TABLE humans ADD CONSTRAINT humans_mortality_state_ck
  CHECK (mortality_state IN ('ACTIVE','DEATH_CONFIRMED','DECEASED'));

CREATE OR REPLACE FUNCTION earth_validate_human_death_state()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.mortality_state = 'ACTIVE' AND NEW.mortality_state NOT IN ('ACTIVE', 'DEATH_CONFIRMED') THEN
    RAISE EXCEPTION 'Human % must be death-confirmed before becoming deceased', NEW.id;
  END IF;
  IF OLD.mortality_state = 'DEATH_CONFIRMED' AND NEW.mortality_state NOT IN ('DEATH_CONFIRMED', 'DECEASED') THEN
    RAISE EXCEPTION 'Human % has an invalid death-state transition', NEW.id;
  END IF;
  IF NEW.mortality_state = 'DECEASED' AND NEW.life_status <> 'deceased' THEN
    RAISE EXCEPTION 'Deceased Human % must have life_status deceased', NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS humans_death_state_trigger ON humans;
CREATE TRIGGER humans_death_state_trigger
  BEFORE UPDATE OF mortality_state, life_status ON humans
  FOR EACH ROW EXECUTE FUNCTION earth_validate_human_death_state();

COMMENT ON COLUMN humans.mortality_state IS
  'Atomic death lifecycle: ACTIVE -> DEATH_CONFIRMED -> DECEASED.';
