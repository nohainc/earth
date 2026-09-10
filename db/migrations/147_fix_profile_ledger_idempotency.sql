-- ledger_entries does not have a unique constraint on correlation_id in all
-- supported databases. Profile settlement is already idempotent through the
-- locked last_settled_game_day, so do not use an unsupported ON CONFLICT form.
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
    ') ON CONFLICT (correlation_id) DO NOTHING;',
    ');'
  );
  IF definition_text LIKE '%ON CONFLICT (correlation_id)%' THEN
    RAISE EXCEPTION 'Cannot remove unsupported profile ledger conflict clause';
  END IF;
  EXECUTE definition_text;
END;
$$;
