-- EARTH ACTIVE MIGRATION: resource analytics trigger V4 nested owner check

CREATE OR REPLACE FUNCTION earth_validate_resource_analytics_owner()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM economic_assets
    WHERE id = NEW.asset_id
      AND asset_kind = 'RESOURCE'
  ) THEN
    RAISE EXCEPTION 'resource analytics asset must be RESOURCE: %', NEW.asset_id;
  END IF;

  -- Keep the house-only record field inside a house-only branch. PostgreSQL
  -- trigger records do not expose columns that belong to another table.
  IF TG_TABLE_NAME = 'house_resource_daily_flow' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM owner_registry
      WHERE economic_id = NEW.house_economic_id
        AND owner_type = 'HOUSE'
    ) THEN
      RAISE EXCEPTION 'house resource flow owner must be HOUSE: %', NEW.house_economic_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
