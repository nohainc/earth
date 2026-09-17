-- EARTH ACTIVE MIGRATION: make established constitutional versions immutable.

CREATE OR REPLACE FUNCTION earth_guard_constitutional_version_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('ACTIVE', 'RETIRED') AND (
    NEW.rule_code IS DISTINCT FROM OLD.rule_code
    OR NEW.authority_type IS DISTINCT FROM OLD.authority_type
    OR NEW.authority_id IS DISTINCT FROM OLD.authority_id
    OR NEW.version IS DISTINCT FROM OLD.version
    OR NEW.value_json IS DISTINCT FROM OLD.value_json
    OR NEW.effective_from_game_day IS DISTINCT FROM OLD.effective_from_game_day
    OR NEW.proposal_id IS DISTINCT FROM OLD.proposal_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  ) THEN
    RAISE EXCEPTION 'Established constitutional rule versions are immutable: %', OLD.id;
  END IF;

  IF OLD.status = 'RETIRED' AND NEW.status <> 'RETIRED' THEN
    RAISE EXCEPTION 'Retired constitutional rule versions cannot be reactivated: %', OLD.id;
  END IF;

  IF OLD.status = 'ACTIVE' AND NEW.status NOT IN ('ACTIVE', 'RETIRED') THEN
    RAISE EXCEPTION 'Active constitutional rule versions may only be retired: %', OLD.id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS constitutional_rule_versions_immutability_guard
  ON constitutional_rule_versions_v5;
CREATE TRIGGER constitutional_rule_versions_immutability_guard
  BEFORE UPDATE ON constitutional_rule_versions_v5
  FOR EACH ROW EXECUTE FUNCTION earth_guard_constitutional_version_immutability();
