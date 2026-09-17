-- EARTH ACTIVE MIGRATION: reject overlapping effective constitutional versions.

CREATE OR REPLACE FUNCTION earth_guard_constitutional_version_overlap()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('ACTIVE', 'RETIRED') AND EXISTS (
    SELECT 1
      FROM constitutional_rule_versions_v5 existing
     WHERE existing.id <> NEW.id
       AND existing.rule_code = NEW.rule_code
       AND existing.authority_type = NEW.authority_type
       AND existing.authority_id = NEW.authority_id
       AND existing.status IN ('ACTIVE', 'RETIRED')
       AND existing.effective_from_game_day <= COALESCE(NEW.effective_to_game_day, 9223372036854775807)
       AND NEW.effective_from_game_day <= COALESCE(existing.effective_to_game_day, 9223372036854775807)
  ) THEN
    RAISE EXCEPTION 'Constitutional rule versions may not overlap for %, %, %',
      NEW.rule_code, NEW.authority_type, NEW.authority_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS constitutional_rule_versions_overlap_guard
  ON constitutional_rule_versions_v5;
CREATE TRIGGER constitutional_rule_versions_overlap_guard
  BEFORE INSERT OR UPDATE OF rule_code, authority_type, authority_id,
    effective_from_game_day, effective_to_game_day, status
  ON constitutional_rule_versions_v5
  FOR EACH ROW EXECUTE FUNCTION earth_guard_constitutional_version_overlap();
