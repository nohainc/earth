-- Prepared, deterministic daily resource deltas. Source tables remain
-- authoritative; this table lets the daily close avoid scanning Buildings for
-- owners whose economic inputs have not changed.
CREATE TABLE daily_settlement_profiles (
  owner_id TEXT PRIMARY KEY,
  owner_kind TEXT NOT NULL CHECK (owner_kind IN ('human', 'city', 'corporation', 'earth')),
  profile_version BIGINT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'dirty' CHECK (status IN ('clean', 'dirty')),
  effective_game_day BIGINT NOT NULL DEFAULT 0,
  last_settled_game_day BIGINT NOT NULL DEFAULT 0,
  credits_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  energy_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  food_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  materials_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  components_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  compute_delta NUMERIC(20,2) NOT NULL DEFAULT 0,
  input_fingerprint TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX daily_settlement_profiles_due_idx
  ON daily_settlement_profiles (status, last_settled_game_day, owner_kind);

-- Existing owners start dirty and are rebuilt before being used.
INSERT INTO daily_settlement_profiles (owner_id, owner_kind)
SELECT id, 'human' FROM humans
ON CONFLICT (owner_id) DO NOTHING;
INSERT INTO daily_settlement_profiles (owner_id, owner_kind)
SELECT id, 'city' FROM cities
ON CONFLICT (owner_id) DO NOTHING;
INSERT INTO daily_settlement_profiles (owner_id, owner_kind)
SELECT id, 'corporation' FROM corporations
ON CONFLICT (owner_id) DO NOTHING;

CREATE OR REPLACE FUNCTION mark_daily_settlement_profile_dirty()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'buildings' THEN
    IF TG_OP <> 'INSERT' AND OLD.owner_id IS NOT NULL THEN
      UPDATE daily_settlement_profiles SET status = 'dirty', updated_at = now() WHERE owner_id = OLD.owner_id;
    END IF;
    IF TG_OP <> 'INSERT' AND OLD.city_id IS NOT NULL THEN
      UPDATE daily_settlement_profiles SET status = 'dirty', updated_at = now() WHERE owner_id = OLD.city_id;
    END IF;
    IF TG_OP <> 'DELETE' AND NEW.owner_id IS NOT NULL THEN
      INSERT INTO daily_settlement_profiles (owner_id, owner_kind, status)
      VALUES (NEW.owner_id, 'human', 'dirty')
      ON CONFLICT (owner_id) DO UPDATE SET status = 'dirty', updated_at = now();
    END IF;
    IF TG_OP <> 'DELETE' AND NEW.city_id IS NOT NULL THEN
      INSERT INTO daily_settlement_profiles (owner_id, owner_kind, status)
      VALUES (NEW.city_id, 'city', 'dirty')
      ON CONFLICT (owner_id) DO UPDATE SET status = 'dirty', updated_at = now();
    END IF;
  ELSIF TG_TABLE_NAME = 'memberships' THEN
    INSERT INTO daily_settlement_profiles (owner_id, owner_kind, status)
    VALUES (COALESCE(NEW.human_id, OLD.human_id), 'human', 'dirty')
    ON CONFLICT (owner_id) DO UPDATE SET status = 'dirty', updated_at = now();
  ELSIF TG_TABLE_NAME = 'humans' AND TG_OP = 'INSERT' THEN
    INSERT INTO daily_settlement_profiles (owner_id, owner_kind, status)
    VALUES (NEW.id, 'human', 'dirty') ON CONFLICT (owner_id) DO NOTHING;
  ELSIF TG_TABLE_NAME = 'cities' AND TG_OP = 'INSERT' THEN
    INSERT INTO daily_settlement_profiles (owner_id, owner_kind, status)
    VALUES (NEW.id, 'city', 'dirty') ON CONFLICT (owner_id) DO NOTHING;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER daily_profile_buildings_dirty
AFTER INSERT OR UPDATE OR DELETE ON buildings
FOR EACH ROW EXECUTE FUNCTION mark_daily_settlement_profile_dirty();
CREATE TRIGGER daily_profile_memberships_dirty
AFTER INSERT OR UPDATE OR DELETE ON memberships
FOR EACH ROW EXECUTE FUNCTION mark_daily_settlement_profile_dirty();
CREATE TRIGGER daily_profile_humans_dirty
AFTER INSERT ON humans
FOR EACH ROW EXECUTE FUNCTION mark_daily_settlement_profile_dirty();
CREATE TRIGGER daily_profile_cities_dirty
AFTER INSERT ON cities
FOR EACH ROW EXECUTE FUNCTION mark_daily_settlement_profile_dirty();
