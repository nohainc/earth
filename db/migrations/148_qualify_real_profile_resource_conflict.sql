-- Qualify the resource upsert conflict target; owner_id is also a function
-- return-column variable in PL/pgSQL.
DO $$
DECLARE
  definition_text TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'earth_catchup_owner_settlement'
  LIMIT 1;
  IF definition_text IS NULL THEN
    RAISE EXCEPTION 'earth_catchup_owner_settlement is not installed';
  END IF;
  definition_text := replace(
    definition_text,
    'ON CONFLICT (owner_id, resource) DO NOTHING',
    'ON CONFLICT ON CONSTRAINT resource_balances_pkey DO NOTHING'
  );
  IF definition_text LIKE '%ON CONFLICT (owner_id, resource)%' THEN
    RAISE EXCEPTION 'Cannot qualify profile resource conflict target';
  END IF;
  EXECUTE definition_text;
END;
$$;
