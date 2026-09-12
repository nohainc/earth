-- Death, Inheritance & House Continuity V2 Plan 4.
-- Private buildings are economically owned by the persistent House. The
-- legacy owner_id remains as the mortal manager/history reference.

-- The legacy dirty-profile trigger omits this V2 column when it creates a
-- profile for a newly observed building owner. Keep the column mandatory, but
-- provide the valid baseline day expected for a dirty profile.
ALTER TABLE daily_settlement_profiles
  ALTER COLUMN effective_from_game_day SET DEFAULT 0;

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS owner_economic_id BIGINT,
  ADD COLUMN IF NOT EXISTS managed_by_human_id TEXT;

UPDATE buildings b
SET owner_economic_id = house_owner.economic_id,
    managed_by_human_id = b.owner_id
FROM humans human
JOIN owner_registry house_owner
  ON house_owner.id = human.house_id
 AND house_owner.owner_type = 'house'
WHERE b.ownership_class = 'private'
  AND b.owner_id = human.id
  AND b.owner_economic_id IS NULL;

ALTER TABLE buildings
  ADD CONSTRAINT buildings_owner_economic_fk
  FOREIGN KEY (owner_economic_id) REFERENCES owner_registry(economic_id);
ALTER TABLE buildings
  ADD CONSTRAINT buildings_private_house_owner_ck
  CHECK (ownership_class <> 'private' OR owner_economic_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS buildings_owner_economic_idx
  ON buildings(owner_economic_id, status);
CREATE INDEX IF NOT EXISTS buildings_managed_by_human_idx
  ON buildings(managed_by_human_id, status);

CREATE OR REPLACE FUNCTION earth_sync_private_building_house_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ownership_class = 'private' AND NEW.owner_id IS NOT NULL THEN
    NEW.managed_by_human_id := NEW.owner_id;
    SELECT house_owner.economic_id INTO NEW.owner_economic_id
    FROM humans human
    JOIN owner_registry house_owner
      ON house_owner.id = human.house_id
     AND house_owner.owner_type = 'house'
     AND house_owner.status = 'active'
    WHERE human.id = NEW.owner_id;
    IF NEW.owner_economic_id IS NULL THEN
      RAISE EXCEPTION 'Private building % requires a Human belonging to an active House', NEW.id;
    END IF;
  ELSIF NEW.ownership_class <> 'private' THEN
    NEW.owner_economic_id := NULL;
    NEW.managed_by_human_id := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS buildings_private_house_owner_trigger ON buildings;
CREATE TRIGGER buildings_private_house_owner_trigger
  BEFORE INSERT OR UPDATE OF owner_id, ownership_class ON buildings
  FOR EACH ROW EXECUTE FUNCTION earth_sync_private_building_house_owner();

COMMENT ON COLUMN buildings.owner_economic_id IS
  'Authoritative Economy V2 owner for private buildings; points to the owning House.';
COMMENT ON COLUMN buildings.managed_by_human_id IS
  'Current or historical Human manager reference; not the economic owner.';
