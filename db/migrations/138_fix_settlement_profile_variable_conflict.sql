-- PostgreSQL output-column names are also PL/pgSQL variables.  The legacy
-- profile rebuild function used an unqualified profile_version assignment,
-- which prevents the first daily run from starting. Prefer table columns for
-- any collision while preserving the existing function body and behaviour.
DO $$
DECLARE
  definition_text TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO definition_text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'earth_rebuild_settlement_profile'
  LIMIT 1;

  IF definition_text IS NOT NULL
     AND definition_text NOT LIKE '%#variable_conflict use_column%' THEN
    definition_text := replace(
      definition_text,
      'AS $function$' || E'\n' || 'DECLARE',
      'AS $function$' || E'\n' || '#variable_conflict use_column' || E'\n' || 'DECLARE'
    );
    EXECUTE definition_text;
  END IF;
END;
$$;
