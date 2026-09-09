-- daily_settlement_profiles.profile_version is BIGINT, while a legacy helper
-- retained an INTEGER result signature. Cast its returned value explicitly so
-- the scheduler can execute the first activated daily run.
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

  IF definition_text IS NOT NULL THEN
    definition_text := replace(
      definition_text,
      E'    p.profile_version,\n    p.status,',
      E'    p.profile_version::INTEGER,\n    p.status,'
    );
    EXECUTE definition_text;
  END IF;
END;
$$;
