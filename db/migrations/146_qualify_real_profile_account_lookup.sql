-- Qualify the account lookup in the real profile settlement function.
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
    E'FROM account_balances\n    WHERE owner_id = p_owner_id AND currency = ''CREDIT''',
    E'FROM account_balances balances\n    WHERE balances.owner_id = p_owner_id AND balances.currency = ''CREDIT'''
  );
  IF definition_text NOT LIKE '%balances.owner_id = p_owner_id%' THEN
    RAISE EXCEPTION 'Cannot qualify account lookup in earth_catchup_owner_settlement';
  END IF;
  EXECUTE definition_text;
END;
$$;
