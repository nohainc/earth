-- owner_id is a RETURNS TABLE variable as well as a table column. Prefer
-- columns throughout the canonical settlement function, including conflict
-- targets, rather than relying on implicit PL/pgSQL resolution.
DO $$
DECLARE
  definition_text TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO definition_text
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_catchup_owner_settlement'
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
