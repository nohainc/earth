-- Building Economy V2 Plan 13: private, publicly funded, and free services.

ALTER TABLE building_catalog DROP CONSTRAINT IF EXISTS building_catalog_service_mode_ck;
UPDATE building_catalog SET service_mode = 'PUBLIC_CONTRACT' WHERE service_mode = 'PUBLIC';
ALTER TABLE building_catalog ADD CONSTRAINT building_catalog_service_mode_ck
  CHECK (service_mode IN ('PRIVATE', 'PUBLIC_CONTRACT', 'FREE'));
ALTER TABLE building_settlement_plans DROP CONSTRAINT IF EXISTS building_settlement_plans_service_mode_ck;
ALTER TABLE building_settlement_plans ADD CONSTRAINT building_settlement_plans_service_mode_ck
  CHECK (service_mode IN ('PRIVATE', 'PUBLIC_CONTRACT', 'FREE'));

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS public_funding_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS funding_source_account_type SMALLINT NOT NULL DEFAULT 3;

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
    1, services.max_price_units, 100
  FROM memberships m
  JOIN humans h ON h.id = m.human_id AND h.life_status = 'active'
  JOIN owner_registry payer ON payer.id = m.human_id
  JOIN LATERAL (
    SELECT p.service_type, MIN(p.default_price_credit_units)::BIGINT AS max_price_units
    FROM building_settlement_plans p
    WHERE p.game_day = p_game_day AND p.city_id = m.city_id
      AND p.service_type IS NOT NULL AND p.service_mode = 'PRIVATE'
      AND p.service_capacity > 0
    GROUP BY p.service_type
  ) services ON TRUE
  ON CONFLICT (game_day, city_id, payer_economic_id, service_type) DO UPDATE SET
    max_price_units = EXCLUDED.max_price_units;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_prepare_public_service_funding(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid public service funding day or shard';
  END IF;

  UPDATE building_settlement_plans p
  SET public_funding_units = CASE WHEN p.service_mode = 'PUBLIC_CONTRACT'
    THEN p.service_capacity * p.default_price_credit_units ELSE 0 END,
    funding_source_account_type = 3
  WHERE p.game_day = p_game_day AND p.shard = p_shard;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN building_catalog.service_mode IS
  'PRIVATE is customer-funded; PUBLIC_CONTRACT is city-funded; FREE has no service revenue.';
