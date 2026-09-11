-- Death & Continuity V2 Plan 24.
-- house_affiliations is authoritative for persistent city/corporation
-- affiliation. memberships remains a one-way compatibility projection for
-- legacy readers until those readers are migrated.

DROP TRIGGER IF EXISTS memberships_house_affiliation_trigger ON memberships;
DROP FUNCTION IF EXISTS earth_sync_house_affiliation();

CREATE OR REPLACE FUNCTION earth_set_house_affiliation(
  p_house_id TEXT,
  p_city_id TEXT,
  p_corporation_id TEXT,
  p_joined_game_day BIGINT,
  p_rank INTEGER DEFAULT 0
)
RETURNS house_affiliations
LANGUAGE plpgsql
AS $$
DECLARE v_result house_affiliations;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM houses WHERE id = p_house_id) THEN
    RAISE EXCEPTION 'House % does not exist', p_house_id;
  END IF;
  IF p_city_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM cities WHERE id = p_city_id) THEN
    RAISE EXCEPTION 'City % does not exist', p_city_id;
  END IF;
  IF p_corporation_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM corporations WHERE id = p_corporation_id) THEN
    RAISE EXCEPTION 'Corporation % does not exist', p_corporation_id;
  END IF;

  INSERT INTO house_affiliations (house_id, city_id, corporation_id, joined_game_day, rank, status)
  VALUES (p_house_id, p_city_id, p_corporation_id, p_joined_game_day, COALESCE(p_rank, 0), 'ACTIVE')
  ON CONFLICT (house_id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    corporation_id = EXCLUDED.corporation_id,
    joined_game_day = EXCLUDED.joined_game_day,
    rank = EXCLUDED.rank,
    status = 'ACTIVE',
    updated_at = CURRENT_TIMESTAMP
  RETURNING * INTO v_result;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_project_house_affiliation_to_memberships(p_house_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE v_human_id TEXT; v_affiliation house_affiliations;
BEGIN
  SELECT current_human_id INTO v_human_id FROM houses WHERE id = p_house_id FOR UPDATE;
  SELECT * INTO v_affiliation FROM house_affiliations
   WHERE house_id = p_house_id AND status = 'ACTIVE';
  IF v_human_id IS NULL OR v_affiliation.house_id IS NULL THEN RETURN; END IF;

  -- Keep one legacy row for the current representative and remove stale
  -- representative rows. This projection never writes back to the authority.
  DELETE FROM memberships m
   USING humans h
   WHERE m.human_id = h.id AND h.house_id = p_house_id AND m.human_id <> v_human_id;
  INSERT INTO memberships (human_id, city_id, corporation_id, joined_game_day)
  VALUES (v_human_id, v_affiliation.city_id, v_affiliation.corporation_id, v_affiliation.joined_game_day)
  ON CONFLICT (human_id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    corporation_id = EXCLUDED.corporation_id,
    joined_game_day = EXCLUDED.joined_game_day;
END;
$$;

CREATE OR REPLACE VIEW house_membership_compatibility AS
SELECT h.current_human_id AS human_id,
       a.house_id,
       a.city_id,
       a.corporation_id,
       a.joined_game_day,
       a.rank,
       a.status
  FROM houses h
  JOIN house_affiliations a ON a.house_id = h.id
 WHERE h.current_human_id IS NOT NULL AND a.status = 'ACTIVE';

-- Existing data is reconciled once from the current representative. Future
-- writes must use earth_set_house_affiliation, not the compatibility table.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT h.id AS house_id, h.current_human_id, m.city_id, m.corporation_id, m.joined_game_day
      FROM houses h JOIN memberships m ON m.human_id = h.current_human_id
     WHERE h.current_human_id IS NOT NULL
  LOOP
    PERFORM earth_set_house_affiliation(r.house_id, r.city_id, r.corporation_id, r.joined_game_day);
    PERFORM earth_project_house_affiliation_to_memberships(r.house_id);
  END LOOP;
END;
$$;
