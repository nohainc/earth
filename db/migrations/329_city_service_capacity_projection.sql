-- Cities, Corporations & Budgets V2 Plan 19.
-- City service quality is derived from settled building output, not mutable
-- scalar capacity fields on cities.

CREATE TABLE city_service_capacity_daily (
  city_id TEXT NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  housing_capacity BIGINT NOT NULL DEFAULT 0 CHECK (housing_capacity >= 0),
  energy_capacity BIGINT NOT NULL DEFAULT 0 CHECK (energy_capacity >= 0),
  connectivity_capacity BIGINT NOT NULL DEFAULT 0 CHECK (connectivity_capacity >= 0),
  health_capacity BIGINT NOT NULL DEFAULT 0 CHECK (health_capacity >= 0),
  service_demand BIGINT NOT NULL DEFAULT 0 CHECK (service_demand >= 0),
  coverage_ratio NUMERIC(12,6) NOT NULL DEFAULT 0 CHECK (coverage_ratio >= 0 AND coverage_ratio <= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (city_id, game_day)
);
CREATE INDEX city_service_capacity_daily_day_idx ON city_service_capacity_daily (game_day, city_id);

CREATE OR REPLACE FUNCTION earth_refresh_city_service_capacity_daily(p_game_day BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE v_count INTEGER;
BEGIN
  INSERT INTO city_service_capacity_daily (
    city_id, game_day, housing_capacity, energy_capacity,
    connectivity_capacity, health_capacity, service_demand, coverage_ratio
  )
  SELECT c.id, p_game_day,
    COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'HOUSING' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0),
    COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'ENERGY' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0),
    COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'CONNECTIVITY' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0),
    COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'HEALTH' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0),
    GREATEST(0, c.residents),
    CASE WHEN c.residents <= 0 THEN 1 ELSE LEAST(1,
      LEAST(
        COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'HOUSING' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0)::NUMERIC / c.residents,
        COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'ENERGY' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0)::NUMERIC / c.residents,
        COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'CONNECTIVITY' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0)::NUMERIC / c.residents,
        COALESCE(SUM(j.service_capacity_units) FILTER (WHERE upper(cat.service_type) = 'HEALTH' AND upper(j.status_after) IN ('ACTIVE', 'DEGRADED')), 0)::NUMERIC / c.residents
      )
    ) END
  FROM cities c
  LEFT JOIN building_settlement_journals j ON j.city_id = c.id AND j.day = p_game_day
  LEFT JOIN buildings b ON b.id = j.building_id
  LEFT JOIN building_catalog cat ON cat.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  GROUP BY c.id, c.residents
  ON CONFLICT (city_id, game_day) DO UPDATE SET
    housing_capacity = EXCLUDED.housing_capacity,
    energy_capacity = EXCLUDED.energy_capacity,
    connectivity_capacity = EXCLUDED.connectivity_capacity,
    health_capacity = EXCLUDED.health_capacity,
    service_demand = EXCLUDED.service_demand,
    coverage_ratio = EXCLUDED.coverage_ratio,
    updated_at = CURRENT_TIMESTAMP;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE city_service_capacity_daily IS
  'Daily city service projection derived from settled Building V2 service capacity; city scalar fields are not authoritative.';
