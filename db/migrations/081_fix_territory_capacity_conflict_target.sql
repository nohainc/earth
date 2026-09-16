-- EARTH ACTIVE MIGRATION: bind Territory capacity refresh to its key.
-- Migration 080 made the refresh idempotent but PostgreSQL requires an
-- explicit conflict target for DO UPDATE. Keep one current projection per
-- Territory, including on databases bridged from the legacy schema.

CREATE UNIQUE INDEX IF NOT EXISTS territory_capacity_state_territory_id_uidx
  ON territory_capacity_state (territory_id);

DO $$
DECLARE
  definition TEXT;
BEGIN
  definition := pg_get_functiondef(
    'earth_refresh_territory_capacity(text,bigint)'::regprocedure
  );
  definition := replace(
    definition,
    'ON CONFLICT DO UPDATE SET',
    'ON CONFLICT (territory_id) DO UPDATE SET'
  );
  EXECUTE definition;
END;
$$;
