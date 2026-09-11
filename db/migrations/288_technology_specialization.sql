-- Technology & Research V2 Plan 36: optional corporation research identity.

CREATE TABLE IF NOT EXISTS corporation_technology_specializations (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  specialization_code TEXT NOT NULL CHECK (specialization_code IN ('INDUSTRY','ENERGY','COMPUTE','AGRICULTURE','CONSTRUCTION','SERVICES')),
  efficiency_bonus_bps INTEGER NOT NULL DEFAULT 1000 CHECK (efficiency_bonus_bps BETWEEN 0 AND 1500),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUPERSEDED','REVOKED')),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, effective_from_game_day),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

CREATE UNIQUE INDEX IF NOT EXISTS corporation_technology_specialization_active_idx
  ON corporation_technology_specializations (corporation_economic_id)
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;

CREATE OR REPLACE FUNCTION earth_corporation_research_specialization_bonus(
  p_corporation_economic_id BIGINT, p_technology_id TEXT, p_game_day BIGINT
)
RETURNS INTEGER LANGUAGE sql STABLE AS $$
  SELECT COALESCE(s.efficiency_bonus_bps, 0)::INTEGER
  FROM technology_catalog t
  LEFT JOIN corporation_technology_specializations s
    ON s.corporation_economic_id = p_corporation_economic_id
   AND s.specialization_code = CASE t.category
      WHEN 'PRODUCTION' THEN 'INDUSTRY' WHEN 'ENERGY' THEN 'ENERGY'
      WHEN 'CONSTRUCTION' THEN 'CONSTRUCTION' WHEN 'SERVICES' THEN 'SERVICES'
      WHEN 'RESEARCH' THEN 'COMPUTE' ELSE NULL END
   AND s.status = 'ACTIVE'
   AND s.effective_from_game_day <= p_game_day
   AND (s.effective_to_game_day IS NULL OR s.effective_to_game_day >= p_game_day)
  WHERE t.id = p_technology_id
  ORDER BY t.effective_from_game_day DESC, t.definition_version DESC, s.effective_from_game_day DESC NULLS LAST
  LIMIT 1;
$$;

ALTER TABLE corporation_research_projects
  ADD COLUMN IF NOT EXISTS specialization_bonus_bps INTEGER NOT NULL DEFAULT 0
    CHECK (specialization_bonus_bps BETWEEN 0 AND 1500);

CREATE OR REPLACE FUNCTION earth_snapshot_research_specialization()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_bonus INTEGER;
BEGIN
  IF NEW.target_type = 'TECHNOLOGY' AND NEW.specialization_bonus_bps = 0 THEN
    v_bonus := earth_corporation_research_specialization_bonus(
      NEW.corporation_economic_id, NEW.target_id, COALESCE(NEW.started_game_day, 0) + 1
    );
    NEW.specialization_bonus_bps := v_bonus;
    IF v_bonus > 0 THEN
      NEW.required_research_points := GREATEST(1, CEIL(
        NEW.required_research_points::NUMERIC * 10000 / (10000 + v_bonus)
      ))::BIGINT;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS corporation_research_specialization_trigger ON corporation_research_projects;
CREATE TRIGGER corporation_research_specialization_trigger
  BEFORE INSERT ON corporation_research_projects
  FOR EACH ROW EXECUTE FUNCTION earth_snapshot_research_specialization();

COMMENT ON TABLE corporation_technology_specializations IS
  'Optional, bounded corporation research specialization; it accelerates matching categories but never grants access.';
