-- EARTH ACTIVE MIGRATION: resource analytics read models
-- These tables are projections only. The ledger and settlement journals remain authoritative.

CREATE TABLE global_resource_daily_state (
  game_day BIGINT NOT NULL,
  asset_id INTEGER NOT NULL REFERENCES economic_assets(id),
  opening_balance_units BIGINT NOT NULL DEFAULT 0 CHECK (opening_balance_units >= 0),
  production_units BIGINT NOT NULL DEFAULT 0 CHECK (production_units >= 0),
  consumption_units BIGINT NOT NULL DEFAULT 0 CHECK (consumption_units >= 0),
  transfer_in_units BIGINT NOT NULL DEFAULT 0 CHECK (transfer_in_units >= 0),
  transfer_out_units BIGINT NOT NULL DEFAULT 0 CHECK (transfer_out_units >= 0),
  closing_balance_units BIGINT NOT NULL DEFAULT 0 CHECK (closing_balance_units >= 0),
  market_volume_units BIGINT NOT NULL DEFAULT 0 CHECK (market_volume_units >= 0),
  average_price_units BIGINT CHECK (average_price_units IS NULL OR average_price_units >= 0),
  shortage_units BIGINT NOT NULL DEFAULT 0 CHECK (shortage_units >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (game_day, asset_id)
);

CREATE TABLE house_resource_daily_flow (
  house_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL,
  asset_id INTEGER NOT NULL REFERENCES economic_assets(id),
  opening_balance_units BIGINT NOT NULL DEFAULT 0 CHECK (opening_balance_units >= 0),
  production_units BIGINT NOT NULL DEFAULT 0 CHECK (production_units >= 0),
  consumption_units BIGINT NOT NULL DEFAULT 0 CHECK (consumption_units >= 0),
  transfer_in_units BIGINT NOT NULL DEFAULT 0 CHECK (transfer_in_units >= 0),
  transfer_out_units BIGINT NOT NULL DEFAULT 0 CHECK (transfer_out_units >= 0),
  closing_balance_units BIGINT NOT NULL DEFAULT 0 CHECK (closing_balance_units >= 0),
  net_flow_units BIGINT NOT NULL DEFAULT 0,
  shortage_units BIGINT NOT NULL DEFAULT 0 CHECK (shortage_units >= 0),
  is_limiting_resource BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (house_economic_id, game_day, asset_id)
);

CREATE INDEX global_resource_daily_state_day_idx ON global_resource_daily_state(game_day DESC);
CREATE INDEX house_resource_daily_flow_day_idx ON house_resource_daily_flow(house_economic_id, game_day DESC);

ALTER TABLE building_settlement_journals
  ADD COLUMN limiting_resources JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN shortage_units JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION earth_validate_resource_analytics_owner()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM economic_assets WHERE id = NEW.asset_id AND asset_kind = 'RESOURCE') THEN
    RAISE EXCEPTION 'resource analytics asset must be RESOURCE: %', NEW.asset_id;
  END IF;
  IF TG_TABLE_NAME = 'house_resource_daily_flow'
     AND NOT EXISTS (SELECT 1 FROM owner_registry WHERE economic_id = NEW.house_economic_id AND owner_type = 'HOUSE') THEN
    RAISE EXCEPTION 'house resource flow owner must be HOUSE: %', NEW.house_economic_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER house_resource_daily_flow_validate
BEFORE INSERT OR UPDATE ON house_resource_daily_flow
FOR EACH ROW EXECUTE FUNCTION earth_validate_resource_analytics_owner();

CREATE TRIGGER global_resource_daily_state_validate
BEFORE INSERT OR UPDATE ON global_resource_daily_state
FOR EACH ROW EXECUTE FUNCTION earth_validate_resource_analytics_owner();
