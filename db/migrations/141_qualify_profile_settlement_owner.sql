-- The function's RETURNS TABLE owner_id name is also a PL/pgSQL variable.
-- Qualify the profile-table update predicate so PostgreSQL cannot confuse it.
DO $$
DECLARE
  definition_text TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO definition_text
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_catchup_owner_settlement'
  LIMIT 1;
  IF definition_text IS NOT NULL THEN
    definition_text := replace(
      definition_text,
      'WHERE owner_id = p_owner_id;',
      'WHERE daily_settlement_profiles.owner_id = p_owner_id;'
    );
    EXECUTE definition_text;
  END IF;
END;
$$;
