-- Building Economy V2 Plan 11: buildings provide services, not CREDIT.

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS service_type TEXT;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS base_service_capacity_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS default_price_credit_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS service_mode TEXT NOT NULL DEFAULT 'PRIVATE';

ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_service_type_ck;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_service_type_ck CHECK (
    service_type IS NULL OR service_type IN ('HOUSING', 'HEALTH', 'CONNECTIVITY', 'TRANSPORT', 'ENTERTAINMENT', 'EDUCATION', 'GENERAL')
  );
ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_service_mode_ck;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_service_mode_ck CHECK (service_mode IN ('PRIVATE', 'PUBLIC'));
ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_service_capacity_ck;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_service_capacity_ck CHECK (base_service_capacity_units >= 0);
ALTER TABLE building_catalog
  DROP CONSTRAINT IF EXISTS building_catalog_service_price_ck;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_service_price_ck CHECK (default_price_credit_units >= 0);

-- Transitional data conversion only. The old value is interpreted as one
-- service-capacity unit per cent so no monetary value is created by planning.
UPDATE building_catalog
SET service_type = COALESCE(service_type, CASE WHEN COALESCE(output_credits, 0) > 0 THEN 'GENERAL' END),
    base_service_capacity_units = CASE
      WHEN base_service_capacity_units = 0 THEN ROUND(COALESCE(output_credits, 0) * 100)::BIGINT
      ELSE base_service_capacity_units
    END,
    default_price_credit_units = CASE
      WHEN default_price_credit_units = 0 AND COALESCE(output_credits, 0) > 0 THEN 100
      ELSE default_price_credit_units
    END
WHERE COALESCE(output_credits, 0) > 0 OR base_service_capacity_units > 0;

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS service_type TEXT;
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS default_price_credit_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS service_mode TEXT NOT NULL DEFAULT 'PRIVATE';

CREATE OR REPLACE FUNCTION earth_finalize_building_service_economics(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building service economics day or shard';
  END IF;

  UPDATE building_settlement_plans p
  SET service_type = c.service_type,
      default_price_credit_units = COALESCE(c.default_price_credit_units, 0),
      service_mode = COALESCE(c.service_mode, 'PRIVATE'),
      service_capacity = ROUND(COALESCE(c.base_service_capacity_units, 0)
        * p.utilization * p.condition_efficiency)::BIGINT
  FROM buildings b
  LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  WHERE p.building_id = b.id AND p.game_day = p_game_day AND p.shard = p_shard;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN building_catalog.output_credits IS
  'Deprecated V1 field; do not use for Economy V2 production or service posting.';
COMMENT ON COLUMN building_catalog.base_service_capacity_units IS
  'Non-monetary service capacity; customer payments are separate funded transfers.';
