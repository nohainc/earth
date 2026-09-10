-- Correct negative resource posting for the real profile settlement function.
-- The function body was installed by migration 144; this forward-only repair
-- keeps existing migration checksums immutable while fixing its upsert logic.
DO $$
DECLARE
  definition_text TEXT;
  old_fragment TEXT := $old$
  INSERT INTO resource_balances (owner_id, resource, amount)
  SELECT p_owner_id, entry.key, GREATEST(0, (entry.value::TEXT)::NUMERIC)
  FROM jsonb_each(v_delta) entry
  WHERE entry.key <> 'credits' AND (entry.value::TEXT)::NUMERIC <> 0
  ON CONFLICT (owner_id, resource) DO UPDATE
    SET amount = GREATEST(0, resource_balances.amount + EXCLUDED.amount);$old$;
  new_fragment TEXT := $new$
  WITH deltas AS (
    SELECT entry.key AS resource, (entry.value::TEXT)::NUMERIC AS amount
    FROM jsonb_each(v_delta) entry
    WHERE entry.key <> 'credits' AND (entry.value::TEXT)::NUMERIC <> 0
  )
  INSERT INTO resource_balances (owner_id, resource, amount)
  SELECT p_owner_id, d.resource, 0
  FROM deltas d
  ON CONFLICT (owner_id, resource) DO NOTHING;

  WITH deltas AS (
    SELECT entry.key AS resource, (entry.value::TEXT)::NUMERIC AS amount
    FROM jsonb_each(v_delta) entry
    WHERE entry.key <> 'credits' AND (entry.value::TEXT)::NUMERIC <> 0
  )
  UPDATE resource_balances balance
  SET amount = GREATEST(0, balance.amount + d.amount)
  FROM deltas d
  WHERE balance.owner_id = p_owner_id AND balance.resource = d.resource;$new$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'earth_catchup_owner_settlement'
  LIMIT 1;
  IF definition_text IS NULL OR position(old_fragment IN definition_text) = 0 THEN
    RAISE EXCEPTION 'Cannot locate resource posting fragment in earth_catchup_owner_settlement';
  END IF;
  EXECUTE replace(definition_text, old_fragment, new_fragment);
END;
$$;
