-- Technology & Research V2 Plan 17: only explicitly selected technologies
-- participate in the patent/licensing system.

UPDATE technology_catalog
SET patentable = CASE code
  WHEN 'clean_energy_systems' THEN TRUE
  WHEN 'food_synthesis' THEN TRUE
  ELSE FALSE
END,
    patent_exclusivity_days = CASE
      WHEN code IN ('clean_energy_systems', 'food_synthesis') THEN GREATEST(patent_exclusivity_days, 3650)
      ELSE 0
    END
WHERE status IN ('ACTIVE', 'DRAFT');

ALTER TABLE technology_catalog
  DROP CONSTRAINT IF EXISTS technology_catalog_patent_terms_ck;
ALTER TABLE technology_catalog
  ADD CONSTRAINT technology_catalog_patent_terms_ck
  CHECK (patentable OR patent_exclusivity_days = 0);

CREATE OR REPLACE FUNCTION earth_technology_is_patentable(
  p_technology_id TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
  SELECT COALESCE((
    SELECT patentable
    FROM technology_catalog
    WHERE id = p_technology_id OR code = p_technology_id
    ORDER BY effective_from_game_day DESC, definition_version DESC
    LIMIT 1
  ), FALSE);
$$;

CREATE OR REPLACE FUNCTION earth_grant_corporation_technology_access(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_access_source TEXT,
  p_source_id TEXT,
  p_effective_from_game_day BIGINT,
  p_effective_to_game_day BIGINT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_access_source NOT IN ('LICENSED', 'GRANTED') THEN
    RAISE EXCEPTION 'Only LICENSED or GRANTED access may be granted explicitly';
  END IF;

  IF p_access_source = 'LICENSED' AND NOT earth_technology_is_patentable(p_technology_id) THEN
    RAISE EXCEPTION 'Technology % is not patentable and cannot be licensed', p_technology_id;
  END IF;

  INSERT INTO corporation_technology_access (
    corporation_economic_id, technology_id, access_source, source_id,
    effective_from_game_day, effective_to_game_day, status
  ) VALUES (
    p_corporation_economic_id, p_technology_id, p_access_source, p_source_id,
    p_effective_from_game_day, p_effective_to_game_day, 'ACTIVE'
  )
  ON CONFLICT (corporation_economic_id, technology_id, access_source, source_id)
  DO UPDATE SET
    effective_from_game_day = EXCLUDED.effective_from_game_day,
    effective_to_game_day = EXCLUDED.effective_to_game_day,
    status = 'ACTIVE',
    updated_at = CURRENT_TIMESTAMP;
END;
$$;

COMMENT ON FUNCTION earth_technology_is_patentable(TEXT) IS
  'Returns the database-authoritative patentability flag for a technology definition.';
