-- Building Economy V2 Plan 12: explicit customer demand for services.

CREATE SEQUENCE IF NOT EXISTS service_demand_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE TABLE IF NOT EXISTS service_demand (
  id BIGINT PRIMARY KEY DEFAULT nextval('service_demand_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  city_id TEXT NOT NULL REFERENCES cities(id),
  payer_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  service_type TEXT NOT NULL,
  requested_units BIGINT NOT NULL CHECK (requested_units > 0),
  max_price_units BIGINT NOT NULL CHECK (max_price_units >= 0),
  priority INTEGER NOT NULL DEFAULT 100 CHECK (priority BETWEEN 0 AND 1000),
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'PARTIALLY_FULFILLED', 'FULFILLED', 'REJECTED', 'CANCELLED')),
  fulfilled_units BIGINT NOT NULL DEFAULT 0 CHECK (fulfilled_units >= 0 AND fulfilled_units <= requested_units),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, city_id, payer_economic_id, service_type)
);

CREATE INDEX IF NOT EXISTS service_demand_matching_idx
  ON service_demand (game_day, city_id, service_type, status, priority, payer_economic_id);
CREATE INDEX IF NOT EXISTS service_demand_payer_idx
  ON service_demand (payer_economic_id, game_day, service_type);

CREATE OR REPLACE FUNCTION earth_prepare_service_demand(p_game_day BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Service demand game day must be non-negative';
  END IF;

  INSERT INTO service_demand (
    game_day, city_id, payer_economic_id, service_type,
    requested_units, max_price_units, priority
  )
  SELECT p_game_day, m.city_id, payer.economic_id, services.service_type,
    1,
    services.max_price_units,
    100
  FROM memberships m
  JOIN humans h ON h.id = m.human_id AND h.life_status = 'active'
  JOIN owner_registry payer ON payer.id = m.human_id
  JOIN LATERAL (
    SELECT p.service_type, MIN(p.default_price_credit_units)::BIGINT AS max_price_units
    FROM building_settlement_plans p
    WHERE p.game_day = p_game_day
      AND p.city_id = m.city_id
      AND p.service_type IS NOT NULL
      AND p.service_capacity > 0
      AND p.service_mode IN ('PRIVATE', 'PUBLIC')
    GROUP BY p.service_type
  ) services ON TRUE
  ON CONFLICT (game_day, city_id, payer_economic_id, service_type) DO UPDATE SET
    max_price_units = EXCLUDED.max_price_units;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE service_demand IS
  'Daily service requests; matching converts delivered units into funded customer payments.';
