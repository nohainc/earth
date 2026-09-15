-- EARTH ACTIVE MIGRATION: resource analytics trigger V4 repair
-- EARTH V4: repair the resource analytics trigger after the house/global
-- projection tables diverged. The shared trigger must not dereference the
-- house-only house_economic_id column for global rows.

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

  IF TG_TABLE_NAME = 'house_resource_daily_flow'
     AND NOT EXISTS (
       SELECT 1
       FROM owner_registry
       WHERE economic_id = NEW.house_economic_id
         AND owner_type = 'HOUSE'
     ) THEN
    RAISE EXCEPTION 'house resource flow owner must be HOUSE: %', NEW.house_economic_id;
  END IF;

  RETURN NEW;
END;
$$;
