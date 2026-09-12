-- Tax governance V2: serialize each tax-rule lineage and prevent overlapping
-- effective intervals when competing approved proposals execute together.

CREATE OR REPLACE FUNCTION earth_tax_rule_versions_are_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND current_setting('earth.tax_rule_allow_close', true) = 'on'
     AND NEW.id IS NOT DISTINCT FROM OLD.id
     AND NEW.tax_rule_id IS NOT DISTINCT FROM OLD.tax_rule_id
     AND NEW.scope IS NOT DISTINCT FROM OLD.scope
     AND NEW.category IS NOT DISTINCT FROM OLD.category
     AND NEW.version IS NOT DISTINCT FROM OLD.version
     AND NEW.effective_from_game_day IS NOT DISTINCT FROM OLD.effective_from_game_day
     AND NEW.rate_bps IS NOT DISTINCT FROM OLD.rate_bps
     AND NEW.tax_base_definition IS NOT DISTINCT FROM OLD.tax_base_definition
     AND NEW.beneficiary_economic_id IS NOT DISTINCT FROM OLD.beneficiary_economic_id
     AND NEW.authorization_proposal_id IS NOT DISTINCT FROM OLD.authorization_proposal_id
     AND NEW.effective_to_game_day IS NOT NULL
     AND NEW.effective_to_game_day >= OLD.effective_from_game_day
  THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Historical tax rule versions are immutable';
END;
$$;

CREATE OR REPLACE FUNCTION earth_tax_rule_versions_no_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.tax_rule_id, 0));
  IF EXISTS (
    SELECT 1
      FROM tax_rule_versions existing
     WHERE existing.tax_rule_id = NEW.tax_rule_id
       AND existing.id <> NEW.id
       AND NEW.effective_from_game_day <= COALESCE(existing.effective_to_game_day, 9223372036854775807)
       AND existing.effective_from_game_day <= COALESCE(NEW.effective_to_game_day, 9223372036854775807)
  ) THEN
    RAISE EXCEPTION 'Tax rule effective interval overlaps an existing version for %', NEW.tax_rule_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tax_rule_versions_no_overlap ON tax_rule_versions;
CREATE TRIGGER tax_rule_versions_no_overlap
BEFORE INSERT OR UPDATE OF tax_rule_id, effective_from_game_day, effective_to_game_day
ON tax_rule_versions
FOR EACH ROW EXECUTE FUNCTION earth_tax_rule_versions_no_overlap();

CREATE OR REPLACE FUNCTION earth_create_tax_rule_version(
  p_tax_rule_id TEXT, p_scope TEXT, p_category TEXT, p_rate_bps INTEGER,
  p_tax_base_definition TEXT, p_beneficiary_economic_id BIGINT,
  p_effective_from_game_day BIGINT, p_authorization_proposal_id TEXT
)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  latest tax_rule_versions%ROWTYPE;
  next_version INTEGER;
  new_id TEXT;
BEGIN
  IF p_effective_from_game_day < 0 THEN
    RAISE EXCEPTION 'Tax effective day must be non-negative';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM proposals
     WHERE id = p_authorization_proposal_id AND decision_status = 'passed'
  ) THEN
    RAISE EXCEPTION 'Tax change requires a passed proposal';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_tax_rule_id, 0));
  SELECT * INTO latest
    FROM tax_rule_versions
   WHERE tax_rule_id = p_tax_rule_id
   ORDER BY version DESC
   LIMIT 1
   FOR UPDATE;

  next_version := COALESCE(latest.version, 0) + 1;
  IF latest.id IS NOT NULL AND p_effective_from_game_day <= latest.effective_from_game_day THEN
    RAISE EXCEPTION 'Tax rule versions cannot be retroactive or overlap: % <= %',
      p_effective_from_game_day, latest.effective_from_game_day;
  END IF;

  IF latest.id IS NOT NULL AND latest.effective_to_game_day IS NULL THEN
    PERFORM set_config('earth.tax_rule_allow_close', 'on', true);
    UPDATE tax_rule_versions
       SET effective_to_game_day = p_effective_from_game_day - 1
     WHERE id = latest.id;
    PERFORM set_config('earth.tax_rule_allow_close', 'off', true);
  END IF;

  new_id := p_tax_rule_id || '-v' || next_version;
  INSERT INTO tax_rule_versions (
    id, tax_rule_id, scope, category, version,
    effective_from_game_day, effective_to_game_day, rate_bps,
    tax_base_definition, beneficiary_economic_id, authorization_proposal_id
  ) VALUES (
    new_id, p_tax_rule_id, p_scope, p_category, next_version,
    p_effective_from_game_day, NULL, p_rate_bps,
    p_tax_base_definition, p_beneficiary_economic_id, p_authorization_proposal_id
  );
  RETURN new_id;
END;
$$;
