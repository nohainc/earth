-- Building Economy V2 Plan 16: explicit operating-cost counterparties.

ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS operating_service_cost_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS operating_cost_recipient_type TEXT NOT NULL DEFAULT 'NONE';
ALTER TABLE building_catalog DROP CONSTRAINT IF EXISTS building_catalog_operating_cost_recipient_ck;
ALTER TABLE building_catalog ADD CONSTRAINT building_catalog_operating_cost_recipient_ck CHECK (
  operating_cost_recipient_type IN ('NONE', 'CITY_TREASURY', 'OUC_TREASURY', 'SERVICE_PROVIDER', 'MAINTENANCE_CONTRACTOR', 'SYSTEM_SINK')
);
ALTER TABLE building_catalog DROP CONSTRAINT IF EXISTS building_catalog_operating_cost_units_ck;
ALTER TABLE building_catalog ADD CONSTRAINT building_catalog_operating_cost_units_ck CHECK (operating_service_cost_units >= 0);

UPDATE building_catalog
SET operating_service_cost_units = CASE
      WHEN operating_service_cost_units = 0 THEN ROUND(COALESCE(daily_operating_credits, 0) * 100)::BIGINT
      ELSE operating_service_cost_units END
WHERE COALESCE(daily_operating_credits, 0) > 0;

ALTER TABLE building_settlement_plans ADD COLUMN IF NOT EXISTS operating_cost_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_plans ADD COLUMN IF NOT EXISTS operating_cost_recipient_type TEXT NOT NULL DEFAULT 'NONE';
ALTER TABLE building_settlement_plans ADD COLUMN IF NOT EXISTS operating_cost_recipient_account_id BIGINT REFERENCES economic_accounts(id);

CREATE OR REPLACE FUNCTION earth_finalize_building_operating_costs(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building operating cost day or shard';
  END IF;

  WITH resolved AS (
    SELECT p.building_id, p.game_day, c.operating_service_cost_units, c.operating_cost_recipient_type,
      CASE c.operating_cost_recipient_type
        WHEN 'CITY_TREASURY' THEN city_account.id
        WHEN 'OUC_TREASURY' THEN ouc_account.id
        WHEN 'SYSTEM_SINK' THEN sink_account.id
        ELSE NULL END AS recipient_account_id
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    LEFT JOIN owner_registry city_owner ON city_owner.id = b.city_id
    LEFT JOIN economic_accounts city_account ON city_account.owner_economic_id = city_owner.economic_id
      AND city_account.asset_id = 1 AND city_account.account_type = 3 AND city_account.status = 'active'
    LEFT JOIN owner_registry ouc_owner ON ouc_owner.id = 'OUC'
    LEFT JOIN economic_accounts ouc_account ON ouc_account.owner_economic_id = ouc_owner.economic_id
      AND ouc_account.asset_id = 1 AND ouc_account.account_type = 3 AND ouc_account.status = 'active'
    LEFT JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
    LEFT JOIN economic_accounts sink_account ON sink_account.owner_economic_id = system_owner.economic_id
      AND sink_account.asset_id = 1 AND sink_account.account_type = 8 AND sink_account.status = 'active'
    WHERE p.game_day = p_game_day AND p.shard = p_shard
  )
  UPDATE building_settlement_plans p
  SET operating_cost_units = CASE WHEN r.recipient_account_id IS NOT NULL THEN r.operating_service_cost_units ELSE 0 END,
      operating_cost_recipient_type = r.operating_cost_recipient_type,
      operating_cost_recipient_account_id = r.recipient_account_id,
      operating_expenses = jsonb_build_object('CREDIT', CASE WHEN r.recipient_account_id IS NOT NULL THEN r.operating_service_cost_units::NUMERIC / 100 ELSE 0 END),
      requirements = CASE WHEN r.recipient_account_id IS NOT NULL
        THEN jsonb_set(p.requirements, '{CREDIT}', to_jsonb(r.operating_service_cost_units::NUMERIC / 100), true)
        ELSE p.requirements - 'CREDIT' END
  FROM resolved r
  WHERE p.building_id = r.building_id AND p.game_day = r.game_day;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON COLUMN building_catalog.daily_operating_credits IS
  'Deprecated V1 field; Economy V2 requires an explicit operating-cost recipient.';
