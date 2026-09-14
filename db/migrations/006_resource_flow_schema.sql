-- EARTH ACTIVE MIGRATION: normalize building resource flows

ALTER TABLE economic_assets
  ADD COLUMN unit_scale BIGINT NOT NULL DEFAULT 1 CHECK (unit_scale > 0),
  ADD COLUMN display_decimals INTEGER NOT NULL DEFAULT 0 CHECK (display_decimals >= 0 AND display_decimals <= 18);

UPDATE economic_assets
   SET unit_scale = CASE WHEN asset_kind = 'CREDIT' THEN 100 ELSE 1000000 END,
       display_decimals = CASE WHEN asset_kind = 'CREDIT' THEN 2 ELSE 0 END;

CREATE TABLE building_catalog_resource_flows (
  catalog_id TEXT NOT NULL REFERENCES building_catalog(id) ON DELETE CASCADE,
  asset_id INTEGER NOT NULL REFERENCES economic_assets(id),
  construction_units BIGINT NOT NULL DEFAULT 0 CHECK (construction_units >= 0),
  operating_input_units BIGINT NOT NULL DEFAULT 0 CHECK (operating_input_units >= 0),
  operating_output_units BIGINT NOT NULL DEFAULT 0 CHECK (operating_output_units >= 0),
  PRIMARY KEY (catalog_id, asset_id)
);

CREATE OR REPLACE FUNCTION earth_validate_building_catalog_resource_flow()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_asset_kind TEXT;
BEGIN
  SELECT asset_kind INTO v_asset_kind FROM economic_assets WHERE id = NEW.asset_id;
  IF v_asset_kind IS DISTINCT FROM 'RESOURCE' THEN
    RAISE EXCEPTION 'building catalog resource flows require RESOURCE assets: %', NEW.asset_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER building_catalog_resource_flow_asset_kind
BEFORE INSERT OR UPDATE OF asset_id ON building_catalog_resource_flows
FOR EACH ROW EXECUTE FUNCTION earth_validate_building_catalog_resource_flow();

-- Convert the last JSON catalog authority into normalized rows before removing
-- the ambiguous columns. Public infrastructure was already converted to
-- CREDIT-only by migration 004, so it contributes no physical-resource rows.
INSERT INTO building_catalog_resource_flows
  (catalog_id, asset_id, construction_units, operating_input_units, operating_output_units)
SELECT bc.id,
       asset.id,
       COALESCE((bc.resource_input_units ->> asset.code)::BIGINT, 0),
       0,
       COALESCE((bc.resource_output_units ->> asset.code)::BIGINT, 0)
  FROM building_catalog bc
  CROSS JOIN economic_assets asset
 WHERE asset.asset_kind = 'RESOURCE'
   AND (bc.resource_input_units ? asset.code OR bc.resource_output_units ? asset.code)
ON CONFLICT (catalog_id, asset_id) DO UPDATE
  SET operating_input_units = EXCLUDED.operating_input_units,
      operating_output_units = EXCLUDED.operating_output_units;

ALTER TABLE building_catalog
  DROP COLUMN resource_input_units,
  DROP COLUMN resource_output_units;
