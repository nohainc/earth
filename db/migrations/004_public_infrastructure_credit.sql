-- EARTH ACTIVE MIGRATION: public infrastructure is CREDIT-only

-- Legacy databases created from the pre-V4 baseline do not yet have the
-- catalog ownership discriminator. This migration is the first forward step
-- that needs it, so add the canonical default before touching public rows.
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS ownership_scope TEXT NOT NULL DEFAULT 'PRIVATE';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'building_catalog'::regclass
       AND pg_get_constraintdef(oid) LIKE '%ownership_scope%'
  ) THEN
    ALTER TABLE building_catalog
      ADD CONSTRAINT building_catalog_ownership_scope_ck
      CHECK (ownership_scope IN ('PRIVATE', 'PUBLIC'));
  END IF;
END;
$$;

UPDATE building_catalog
SET resource_input_units = '{}'::jsonb,
    resource_output_units = '{}'::jsonb,
    definition_version = 'territory-capacity-v2'
WHERE ownership_scope = 'PUBLIC';

ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_public_credit_only_ck
  CHECK (
    ownership_scope <> 'PUBLIC'
    OR (
      resource_input_units = '{}'::jsonb
      AND resource_output_units = '{}'::jsonb
      AND service_type IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION earth_validate_public_catalog_effect()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  ownership_scope TEXT;
BEGIN
  SELECT bc.ownership_scope INTO ownership_scope
    FROM building_catalog bc
   WHERE bc.id = NEW.catalog_id;
  IF ownership_scope = 'PUBLIC' AND NEW.effect_code NOT IN (
    'POPULATION_CAPACITY', 'PRIVATE_SLOTS', 'PUBLIC_SLOTS', 'SERVICE_CAPACITY',
    'HOUSING_CAPACITY', 'HEALTH_CAPACITY', 'ENERGY_CAPACITY', 'CONNECTIVITY_CAPACITY'
  ) THEN
    RAISE EXCEPTION 'Public infrastructure may define only service or capacity effects';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER building_catalog_public_effect_integrity
BEFORE INSERT OR UPDATE OF catalog_id, effect_code ON building_catalog_effects
FOR EACH ROW EXECUTE FUNCTION earth_validate_public_catalog_effect();
