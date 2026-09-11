-- Building Economy V2 Plan 14: deterministic city/service demand matching.

CREATE SEQUENCE IF NOT EXISTS service_allocation_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE TABLE IF NOT EXISTS service_allocations (
  id BIGINT PRIMARY KEY DEFAULT nextval('service_allocation_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  demand_id BIGINT NOT NULL REFERENCES service_demand(id) ON DELETE CASCADE,
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  city_id TEXT NOT NULL REFERENCES cities(id),
  service_type TEXT NOT NULL,
  delivered_units BIGINT NOT NULL CHECK (delivered_units > 0),
  price_units BIGINT NOT NULL CHECK (price_units >= 0),
  status TEXT NOT NULL DEFAULT 'RESOLVED' CHECK (status IN ('RESOLVED', 'POSTED', 'CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, demand_id, building_id)
);

CREATE INDEX IF NOT EXISTS service_allocations_group_idx
  ON service_allocations (game_day, city_id, service_type, building_id);
CREATE INDEX IF NOT EXISTS service_allocations_demand_idx
  ON service_allocations (demand_id, game_day);

CREATE OR REPLACE FUNCTION earth_match_service_demand(p_game_day BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Service matching game day must be non-negative';
  END IF;

  DELETE FROM service_allocations WHERE game_day = p_game_day;

  WITH demand_rows AS (
    SELECT d.*, COALESCE(SUM(d.requested_units) OVER (
      PARTITION BY d.city_id, d.service_type
      ORDER BY d.priority DESC, d.payer_economic_id, d.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::BIGINT AS demand_start,
      SUM(d.requested_units) OVER (
        PARTITION BY d.city_id, d.service_type
        ORDER BY d.priority DESC, d.payer_economic_id, d.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )::BIGINT AS demand_end
    FROM service_demand d
    WHERE d.game_day = p_game_day AND d.status IN ('PENDING', 'PARTIALLY_FULFILLED')
  ), supply_rows AS (
    SELECT p.*, b.city_id,
      COALESCE(p.default_price_credit_units, 0) AS price_units,
      COALESCE(SUM(p.service_capacity) OVER (
        PARTITION BY p.city_id, p.service_type
        ORDER BY p.default_price_credit_units, p.condition_efficiency DESC, p.building_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ), 0)::BIGINT AS supply_start,
      SUM(p.service_capacity) OVER (
        PARTITION BY p.city_id, p.service_type
        ORDER BY p.default_price_credit_units, p.condition_efficiency DESC, p.building_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )::BIGINT AS supply_end
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    WHERE p.game_day = p_game_day AND p.service_mode = 'PRIVATE'
      AND p.service_type IS NOT NULL AND p.service_capacity > 0
  ), matches AS (
    SELECT d.id AS demand_id, s.building_id, d.city_id, d.service_type,
      GREATEST(0, LEAST(d.demand_end, s.supply_end) - GREATEST(d.demand_start, s.supply_start))::BIGINT AS delivered_units,
      s.price_units
    FROM demand_rows d
    JOIN supply_rows s ON s.city_id = d.city_id AND s.service_type = d.service_type
      AND s.price_units <= d.max_price_units
  )
  INSERT INTO service_allocations (
    game_day, demand_id, building_id, city_id, service_type,
    delivered_units, price_units
  )
  SELECT p_game_day, demand_id, building_id, city_id, service_type, delivered_units, price_units
  FROM matches
  WHERE delivered_units > 0
  ON CONFLICT (game_day, demand_id, building_id) DO UPDATE SET
    delivered_units = EXCLUDED.delivered_units,
    price_units = EXCLUDED.price_units,
    status = 'RESOLVED';

  WITH fulfilled AS (
    SELECT d.id, COALESCE(SUM(a.delivered_units), 0)::BIGINT AS delivered
    FROM service_demand d
    LEFT JOIN service_allocations a ON a.demand_id = d.id AND a.game_day = p_game_day
    WHERE d.game_day = p_game_day
    GROUP BY d.id
  )
  UPDATE service_demand d
  SET fulfilled_units = f.delivered,
      status = CASE WHEN f.delivered >= d.requested_units THEN 'FULFILLED'
                    WHEN f.delivered > 0 THEN 'PARTIALLY_FULFILLED'
                    ELSE 'REJECTED' END
  FROM fulfilled f
  WHERE d.id = f.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE service_allocations IS
  'Set-wise city/service delivery allocation; payment is a later Economy V2 posting step.';
