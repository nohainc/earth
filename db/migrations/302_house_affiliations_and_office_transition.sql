-- Death & Continuity V2 Plan 14.
-- Affiliations belong to the persistent House; offices belong to a mortal Human.
CREATE TABLE IF NOT EXISTS house_affiliations (
  house_id TEXT PRIMARY KEY REFERENCES houses(id) ON DELETE CASCADE,
  city_id TEXT REFERENCES cities(id),
  corporation_id TEXT REFERENCES corporations(id),
  joined_game_day BIGINT NOT NULL,
  rank INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS house_affiliations_city_idx ON house_affiliations(city_id, status);
CREATE INDEX IF NOT EXISTS house_affiliations_corporation_idx ON house_affiliations(corporation_id, status);

INSERT INTO house_affiliations (house_id, city_id, corporation_id, joined_game_day, status)
SELECT h.house_id, m.city_id, m.corporation_id, MIN(m.joined_game_day), 'ACTIVE'
  FROM memberships m JOIN humans h ON h.id = m.human_id
 WHERE h.life_status IN ('active', 'pending')
 GROUP BY h.house_id, m.city_id, m.corporation_id
ON CONFLICT (house_id) DO UPDATE SET
  city_id = EXCLUDED.city_id,
  corporation_id = EXCLUDED.corporation_id,
  status = 'ACTIVE',
  updated_at = CURRENT_TIMESTAMP;

CREATE OR REPLACE FUNCTION earth_sync_house_affiliation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_house_id TEXT;
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT house_id INTO v_house_id FROM humans WHERE id = NEW.human_id;
    IF v_house_id IS NOT NULL THEN
      INSERT INTO house_affiliations (house_id, city_id, corporation_id, joined_game_day, status)
      VALUES (v_house_id, NEW.city_id, NEW.corporation_id, NEW.joined_game_day, 'ACTIVE')
      ON CONFLICT (house_id) DO UPDATE SET
        city_id = EXCLUDED.city_id,
        corporation_id = EXCLUDED.corporation_id,
        status = 'ACTIVE',
        updated_at = CURRENT_TIMESTAMP;
    END IF;
  ELSE
    SELECT house_id INTO v_house_id FROM humans WHERE id = OLD.human_id;
    IF v_house_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM memberships m JOIN humans h ON h.id = m.human_id
       WHERE h.house_id = v_house_id AND (m.city_id IS NOT NULL OR m.corporation_id IS NOT NULL)
    ) THEN
      UPDATE house_affiliations SET status = 'INACTIVE', updated_at = CURRENT_TIMESTAMP WHERE house_id = v_house_id;
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS memberships_house_affiliation_trigger ON memberships;
CREATE TRIGGER memberships_house_affiliation_trigger
AFTER INSERT OR UPDATE OF city_id, corporation_id, joined_game_day OR DELETE ON memberships
FOR EACH ROW EXECUTE FUNCTION earth_sync_house_affiliation();
