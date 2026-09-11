-- Human Life & Needs V2: aggregate need satisfaction, not manual purchases.
CREATE TABLE IF NOT EXISTS human_daily_needs (
  human_id TEXT NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  city_id TEXT REFERENCES cities(id),
  food_satisfaction NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (food_satisfaction BETWEEN 0 AND 1),
  housing_satisfaction NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (housing_satisfaction BETWEEN 0 AND 1),
  energy_satisfaction NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (energy_satisfaction BETWEEN 0 AND 1),
  healthcare_access NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (healthcare_access BETWEEN 0 AND 1),
  connectivity_access NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (connectivity_access BETWEEN 0 AND 1),
  life_quality NUMERIC(12,6) NOT NULL DEFAULT 1 CHECK (life_quality BETWEEN 0 AND 1),
  source TEXT NOT NULL DEFAULT 'daily-needs-v2',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (human_id, game_day)
);
CREATE INDEX IF NOT EXISTS human_daily_needs_day_idx ON human_daily_needs (game_day, city_id, human_id);

CREATE OR REPLACE FUNCTION earth_refresh_human_daily_needs(p_game_day BIGINT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
  INSERT INTO human_daily_needs (human_id, game_day, city_id, food_satisfaction, housing_satisfaction, energy_satisfaction, healthcare_access, connectivity_access, life_quality)
  SELECT h.id, p_game_day, m.city_id,
    LEAST(1, GREATEST(0, COALESCE(lm.food_used / NULLIF(lm.food, 0), CASE WHEN lm.id IS NULL THEN 1 ELSE 0 END))),
    CASE WHEN c.id IS NULL OR c.residents <= 0 THEN 1 ELSE LEAST(1, GREATEST(0, c.housing_capacity::NUMERIC / c.residents)) END,
    CASE WHEN c.id IS NULL OR c.residents <= 0 THEN 1 ELSE LEAST(1, GREATEST(0, c.energy_capacity::NUMERIC / c.residents)) END,
    CASE WHEN c.id IS NULL THEN 0.5 ELSE LEAST(1, GREATEST(0, c.health_capacity::NUMERIC / 100)) END,
    CASE WHEN c.id IS NULL OR c.residents <= 0 THEN 1 ELSE LEAST(1, GREATEST(0, c.connectivity_capacity::NUMERIC / c.residents)) END,
    (LEAST(1, GREATEST(0, COALESCE(lm.food_used / NULLIF(lm.food, 0), CASE WHEN lm.id IS NULL THEN 1 ELSE 0 END)))
      + CASE WHEN c.id IS NULL OR c.residents <= 0 THEN 1 ELSE LEAST(1, GREATEST(0, c.housing_capacity::NUMERIC / c.residents)) END
      + CASE WHEN c.id IS NULL OR c.residents <= 0 THEN 1 ELSE LEAST(1, GREATEST(0, c.energy_capacity::NUMERIC / c.residents)) END
      + CASE WHEN c.id IS NULL THEN 0.5 ELSE LEAST(1, GREATEST(0, c.health_capacity::NUMERIC / 100)) END
      + CASE WHEN c.id IS NULL OR c.residents <= 0 THEN 1 ELSE LEAST(1, GREATEST(0, c.connectivity_capacity::NUMERIC / c.residents)) END) / 5
  FROM humans h
  LEFT JOIN memberships m ON m.human_id = h.id
  LEFT JOIN cities c ON c.id = m.city_id
  LEFT JOIN LATERAL (SELECT id, food, food_used FROM personal_life_maintenance WHERE human_id = h.id AND game_day = p_game_day ORDER BY id DESC LIMIT 1) lm ON TRUE
  WHERE h.life_status = 'active'
  ON CONFLICT (human_id, game_day) DO UPDATE SET city_id = EXCLUDED.city_id, food_satisfaction = EXCLUDED.food_satisfaction, housing_satisfaction = EXCLUDED.housing_satisfaction, energy_satisfaction = EXCLUDED.energy_satisfaction, healthcare_access = EXCLUDED.healthcare_access, connectivity_access = EXCLUDED.connectivity_access, life_quality = EXCLUDED.life_quality, updated_at = CURRENT_TIMESTAMP;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;
