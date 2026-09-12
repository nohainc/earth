-- Death, Inheritance & House Continuity V2 Plan 1.
-- A House is the persistent player principal; Humans are mortal generations.

ALTER TABLE houses
  ADD COLUMN IF NOT EXISTS account_id TEXT,
  ADD COLUMN IF NOT EXISTS current_human_id TEXT,
  ADD COLUMN IF NOT EXISTS dynasty_legacy BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS generation INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE';

ALTER TABLE humans
  ADD COLUMN IF NOT EXISTS house_id TEXT;

-- Existing installations used the authentication email as the house key.
-- Preserve that identity while moving the relationship onto an explicit FK.
UPDATE houses
SET account_id = COALESCE(account_id, email),
    generation = GREATEST(
      COALESCE(generation, 1),
      COALESCE((SELECT MAX(generation) FROM house_lineage_records l WHERE l.house_id = houses.id), 1)
    )
WHERE account_id IS NULL;

INSERT INTO houses (id, account_id, email, house_name, founder_human_id, generation, status)
SELECT 'HOUSE-' || h.id,
       COALESCE(ac.email, h.account_id, h.id),
       COALESCE(ac.email, h.account_id, h.id || '@legacy.invalid'),
       'House ' || h.display_name,
       h.id,
       1,
       'ACTIVE'
FROM humans h
LEFT JOIN auth_credentials ac ON ac.human_id = h.id
WHERE NOT EXISTS (
  SELECT 1 FROM house_lineage_records l WHERE l.human_id = h.id
)
  AND NOT EXISTS (
    SELECT 1 FROM houses existing
    WHERE existing.founder_human_id = h.id
       OR existing.email = COALESCE(ac.email, h.account_id, h.id || '@legacy.invalid')
  );

UPDATE humans h
SET house_id = COALESCE(
  (SELECT l.house_id FROM house_lineage_records l WHERE l.human_id = h.id ORDER BY l.generation DESC, l.created_at DESC LIMIT 1),
  (SELECT house.id FROM houses house WHERE house.founder_human_id = h.id LIMIT 1),
  'HOUSE-' || h.id
)
WHERE h.house_id IS NULL;

-- A legacy house can have several historical Humans, but only one active
-- incumbent. The most recent active lineage record wins deterministically.
UPDATE houses house
SET current_human_id = (
      SELECT h.id
      FROM humans h
      LEFT JOIN house_lineage_records l ON l.human_id = h.id AND l.house_id = house.id
      WHERE h.house_id = house.id AND h.life_status = 'active'
      ORDER BY l.is_incumbent DESC NULLS LAST, l.generation DESC NULLS LAST, h.created_at DESC, h.id
      LIMIT 1
    ),
    generation = GREATEST(
      house.generation,
      COALESCE((
        SELECT l.generation
        FROM humans h
        JOIN house_lineage_records l ON l.human_id = h.id AND l.house_id = house.id
        WHERE h.house_id = house.id AND h.life_status = 'active'
        ORDER BY l.is_incumbent DESC NULLS LAST, l.generation DESC NULLS LAST, h.created_at DESC, h.id
        LIMIT 1
      ), 1)
    )
WHERE house.current_human_id IS NULL
  AND EXISTS (SELECT 1 FROM humans h WHERE h.house_id = house.id AND h.life_status = 'active');

ALTER TABLE houses
  ALTER COLUMN account_id SET NOT NULL;

ALTER TABLE humans
  ALTER COLUMN house_id SET NOT NULL;

ALTER TABLE houses
  DROP CONSTRAINT IF EXISTS houses_status_ck;
ALTER TABLE houses
  ADD CONSTRAINT houses_status_ck CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED'));

ALTER TABLE houses
  DROP CONSTRAINT IF EXISTS houses_account_id_uq;
ALTER TABLE houses
  ADD CONSTRAINT houses_account_id_uq UNIQUE (account_id);

ALTER TABLE humans
  DROP CONSTRAINT IF EXISTS humans_house_fk;
ALTER TABLE humans
  ADD CONSTRAINT humans_house_fk FOREIGN KEY (house_id) REFERENCES houses(id);

ALTER TABLE houses
  DROP CONSTRAINT IF EXISTS houses_current_human_fk;
ALTER TABLE houses
  ADD CONSTRAINT houses_current_human_fk FOREIGN KEY (current_human_id) REFERENCES humans(id);

CREATE INDEX IF NOT EXISTS humans_house_idx ON humans (house_id, life_status, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS humans_one_active_per_house_idx
  ON humans (house_id)
  WHERE life_status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS houses_one_current_human_idx
  ON houses (current_human_id)
  WHERE current_human_id IS NOT NULL;

CREATE OR REPLACE FUNCTION earth_validate_house_incumbent()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE v_house_id TEXT;
BEGIN
  IF NEW.life_status = 'active' THEN
    IF NEW.house_id IS NULL THEN
      RAISE EXCEPTION 'An active Human must belong to a House';
    END IF;
    SELECT current_human_id INTO v_house_id FROM houses WHERE id = NEW.house_id FOR UPDATE;
    IF v_house_id IS NOT NULL AND v_house_id <> NEW.id THEN
      RAISE EXCEPTION 'House % already has active Human %', NEW.house_id, v_house_id;
    END IF;
    UPDATE houses SET current_human_id = NEW.id, generation = GREATEST(generation, 1) WHERE id = NEW.house_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.life_status = 'active' AND NEW.house_id IS DISTINCT FROM OLD.house_id THEN
    UPDATE houses SET current_human_id = NULL WHERE id = OLD.house_id AND current_human_id = OLD.id;
  ELSIF TG_OP = 'UPDATE' AND OLD.life_status = 'active' AND NEW.life_status <> 'active' THEN
    UPDATE houses SET current_human_id = NULL WHERE id = NEW.house_id AND current_human_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS humans_house_incumbent_trigger ON humans;
CREATE TRIGGER humans_house_incumbent_trigger
  AFTER INSERT OR UPDATE OF house_id, life_status ON humans
  FOR EACH ROW EXECUTE FUNCTION earth_validate_house_incumbent();

COMMENT ON TABLE houses IS
  'Persistent player principal. Economic relationships remain with the House across mortal Human generations.';
COMMENT ON COLUMN houses.account_id IS
  'Stable authentication/account principal; unlike humans.account_id, this survives rebirth.';
COMMENT ON COLUMN houses.current_human_id IS
  'The sole active mortal representative of this House.';
COMMENT ON COLUMN humans.house_id IS
  'Required persistent House ownership for every mortal generation.';
