-- Technology & Research V2 Plan 10: corporation-level technology access.

CREATE TABLE IF NOT EXISTS corporation_technology_access (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  technology_id TEXT NOT NULL REFERENCES technology_catalog(id),
  access_source TEXT NOT NULL CHECK (access_source IN ('RESEARCHED', 'LICENSED', 'GRANTED')),
  source_id TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXPIRED', 'REVOKED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, technology_id, access_source, source_id),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE INDEX IF NOT EXISTS corporation_technology_access_lookup_idx
  ON corporation_technology_access (corporation_economic_id, technology_id, effective_from_game_day, effective_to_game_day)
  WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS corporation_technology_access_expiry_idx
  ON corporation_technology_access (effective_to_game_day)
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NOT NULL;

CREATE OR REPLACE FUNCTION earth_sync_corporation_researched_technology_access(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Technology access game day must be non-negative';
  END IF;

  INSERT INTO corporation_technology_access (
    corporation_economic_id, technology_id, access_source, source_id,
    effective_from_game_day, status
  )
  SELECT p.corporation_economic_id, p.target_id, 'RESEARCHED', p.id,
    COALESCE(p.completed_game_day, p_game_day), 'ACTIVE'
  FROM corporation_research_projects p
  WHERE p.target_type = 'TECHNOLOGY'
    AND p.status = 'COMPLETED'
  ON CONFLICT (corporation_economic_id, technology_id, access_source, source_id)
  DO UPDATE SET status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_corporation_has_technology_access(
  p_corporation_economic_id BIGINT,
  p_technology_id TEXT,
  p_game_day BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM corporation_technology_access a
    WHERE a.corporation_economic_id = p_corporation_economic_id
      AND a.technology_id = p_technology_id
      AND a.status = 'ACTIVE'
      AND a.effective_from_game_day <= p_game_day
      AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
  );
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
