-- Technology & Research V2 Plan 31: one access decision for every consumer.

CREATE OR REPLACE FUNCTION earth_resolve_corporation_technology_access(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_game_day BIGINT
)
RETURNS TABLE (has_access BOOLEAN, access_reason TEXT, source_id TEXT)
LANGUAGE sql STABLE AS $$
  SELECT TRUE, candidate.access_reason, candidate.source_id
  FROM (
    SELECT 'PUBLIC_DOMAIN'::TEXT AS access_reason,
           'PUBLIC_DOMAIN:' || d.technology_id AS source_id, 1 AS precedence
    FROM technology_public_domain d
    WHERE d.technology_id = p_technology_id
      AND d.effective_from_game_day <= p_game_day
    UNION ALL
    SELECT a.access_source::TEXT AS access_reason, a.source_id, 2 AS precedence
    FROM corporation_technology_access a
    WHERE a.corporation_economic_id = p_corporation_economic_id
      AND a.technology_id = p_technology_id
      AND a.status = 'ACTIVE'
      AND a.effective_from_game_day <= p_game_day
      AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
      AND (
        a.access_source <> 'LICENSED'
        OR EXISTS (
          SELECT 1 FROM technology_license_contracts c
          WHERE c.id = a.source_id AND c.status = 'ACTIVE'
            AND c.paid_through_game_day >= p_game_day
        )
      )
  ) candidate
  ORDER BY candidate.precedence,
    CASE candidate.access_reason
      WHEN 'RESEARCHED' THEN 1 WHEN 'GRANTED' THEN 2 WHEN 'LICENSED' THEN 3 ELSE 4
    END,
    candidate.source_id
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION earth_corporation_has_technology_access(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_game_day BIGINT
)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT r.has_access FROM earth_resolve_corporation_technology_access(
    p_corporation_economic_id, p_technology_id, p_game_day
  ) r), FALSE);
$$;

CREATE OR REPLACE FUNCTION earth_sync_technology_license_access_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE corporation_technology_access
  SET status = CASE WHEN NEW.status = 'ACTIVE' THEN 'ACTIVE' ELSE 'REVOKED' END,
      updated_at = CURRENT_TIMESTAMP
  WHERE access_source = 'LICENSED' AND source_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS technology_license_access_status_trigger ON technology_license_contracts;
CREATE TRIGGER technology_license_access_status_trigger
  AFTER UPDATE OF status ON technology_license_contracts
  FOR EACH ROW EXECUTE FUNCTION earth_sync_technology_license_access_status();

COMMENT ON FUNCTION earth_resolve_corporation_technology_access(BIGINT, TEXT, BIGINT) IS
  'Canonical day-effective technology authorization resolver; returns the winning reason and source.';
