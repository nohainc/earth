-- Qualify the applied-run conflict target for PL/pgSQL's owner_id return
-- variable.
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
    'ON CONFLICT (owner_id, game_day) DO UPDATE',
    'ON CONFLICT ON CONSTRAINT daily_settlement_profile_runs_pkey DO UPDATE'
  );
  IF definition_text LIKE '%ON CONFLICT (owner_id, game_day)%' THEN
    RAISE EXCEPTION 'Cannot qualify profile run conflict target';
  END IF;
  EXECUTE definition_text;
END;
$$;
