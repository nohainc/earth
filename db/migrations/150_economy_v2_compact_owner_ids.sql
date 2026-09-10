-- Economy V2 foundation: add compact, stable identifiers for economic tables.
-- Existing owner_registry IDs and all domain foreign keys remain unchanged.

CREATE SEQUENCE IF NOT EXISTS owner_registry_economic_id_seq
  AS BIGINT
  START WITH 1001
  INCREMENT BY 1
  MINVALUE 1;

ALTER TABLE owner_registry
  ADD COLUMN IF NOT EXISTS economic_id BIGINT;

-- Reserve stable low IDs for the two built-in system owners when present.
UPDATE owner_registry
SET economic_id = CASE id WHEN 'OUC' THEN 1 WHEN 'SYSTEM' THEN 2 END,
    updated_at = CURRENT_TIMESTAMP
WHERE id IN ('OUC', 'SYSTEM')
  AND economic_id IS NULL;

-- Allocate all other IDs from one sequence. Ordering keeps fresh installations
-- deterministic without changing the canonical TEXT owner IDs.
WITH pending AS (
  SELECT id
  FROM owner_registry
  WHERE economic_id IS NULL
  ORDER BY id
  FOR UPDATE
)
UPDATE owner_registry r
SET economic_id = nextval('owner_registry_economic_id_seq'),
    updated_at = CURRENT_TIMESTAMP
FROM pending
WHERE r.id = pending.id;

SELECT setval(
  'owner_registry_economic_id_seq',
  GREATEST(1000, COALESCE((SELECT MAX(economic_id) FROM owner_registry), 1000)),
  true
);

ALTER TABLE owner_registry
  ALTER COLUMN economic_id SET DEFAULT nextval('owner_registry_economic_id_seq'),
  ALTER COLUMN economic_id SET NOT NULL;

ALTER TABLE owner_registry
  ADD CONSTRAINT owner_registry_economic_id_key UNIQUE (economic_id);

CREATE INDEX IF NOT EXISTS owner_registry_economic_type_idx
  ON owner_registry (economic_id, owner_type, status);

CREATE OR REPLACE FUNCTION earth_prevent_owner_economic_id_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.economic_id IS DISTINCT FROM OLD.economic_id THEN
    RAISE EXCEPTION 'owner_registry.economic_id is immutable for owner %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS owner_registry_economic_id_immutable ON owner_registry;
CREATE TRIGGER owner_registry_economic_id_immutable
BEFORE UPDATE OF economic_id ON owner_registry
FOR EACH ROW
EXECUTE FUNCTION earth_prevent_owner_economic_id_change();
