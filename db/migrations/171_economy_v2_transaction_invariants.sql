-- Economy V2 Plan 22: restore transaction invariants after entry partitioning.

CREATE OR REPLACE FUNCTION earth_assert_economic_transaction_balanced()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  transaction_key BIGINT;
  transaction_keys BIGINT[];
  entry_count BIGINT;
  unbalanced_count BIGINT;
BEGIN
  IF TG_TABLE_NAME = 'economic_transactions' THEN
    transaction_keys := ARRAY[COALESCE(NEW.id, OLD.id)];
  ELSE
    transaction_keys := ARRAY[COALESCE(NEW.transaction_id, OLD.transaction_id)];
    IF TG_OP = 'UPDATE' AND OLD.transaction_id IS DISTINCT FROM NEW.transaction_id THEN
      transaction_keys := array_append(transaction_keys, OLD.transaction_id);
    END IF;
  END IF;

  FOREACH transaction_key IN ARRAY transaction_keys LOOP
    SELECT COUNT(*) INTO entry_count
    FROM economic_entries WHERE transaction_id = transaction_key;
    IF entry_count < 2 THEN
      RAISE EXCEPTION 'Economic transaction % requires at least two entries', transaction_key;
    END IF;

    SELECT COUNT(*) INTO unbalanced_count
    FROM (
      SELECT a.asset_id
      FROM economic_entries e
      JOIN economic_accounts a ON a.id = e.account_id
      WHERE e.transaction_id = transaction_key
      GROUP BY a.asset_id
      HAVING SUM(e.delta) <> 0
    ) unbalanced;
    IF unbalanced_count > 0 THEN
      RAISE EXCEPTION 'Economic transaction % is not balanced per asset', transaction_key;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

-- Partitioning replaced the original table and therefore dropped its
-- entry-level constraint trigger. PostgreSQL does not allow constraint
-- triggers directly on a partitioned parent, so install the deferred trigger
-- on every current leaf partition, including the default partition.
DO $$
DECLARE
  partition_name REGCLASS;
BEGIN
  FOR partition_name IN
    SELECT child.oid::REGCLASS
    FROM pg_inherits inheritance
    JOIN pg_class child ON child.oid = inheritance.inhrelid
    JOIN pg_namespace namespace ON namespace.oid = child.relnamespace
    WHERE inheritance.inhparent = 'economic_entries'::REGCLASS
      AND namespace.nspname = current_schema()
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS economic_entries_balance_check ON %s', partition_name);
    EXECUTE format(
      'CREATE CONSTRAINT TRIGGER economic_entries_balance_check
       AFTER INSERT OR UPDATE OR DELETE ON %s
       DEFERRABLE INITIALLY DEFERRED
       FOR EACH ROW
       EXECUTE FUNCTION earth_assert_economic_transaction_balanced()',
      partition_name
    );
  END LOOP;
END;
$$;

-- Make settlement batches reject a single final net effect immediately, rather
-- than waiting for the deferred trigger at transaction commit.
DO $$
DECLARE
  definition_text TEXT;
  old_declaration TEXT := '  invalid_count BIGINT;';
  new_declaration TEXT := E'  invalid_count BIGINT;\n  v_final_entry_count BIGINT;';
  old_guard TEXT := $old$
  IF jsonb_typeof(p_effects) <> 'array' OR jsonb_array_length(p_effects) = 0 THEN
    RAISE EXCEPTION 'Settlement batch requires at least one effect';
  END IF;$old$;
  new_guard TEXT := $new$
  IF jsonb_typeof(p_effects) <> 'array' OR jsonb_array_length(p_effects) = 0 THEN
    RAISE EXCEPTION 'Settlement batch requires at least one effect';
  END IF;
  SELECT COUNT(*) INTO v_final_entry_count
  FROM (
    SELECT (item->>'account_id')::BIGINT AS account_id,
           SUM((item->>'delta')::BIGINT) AS delta
    FROM jsonb_array_elements(p_effects) item
    GROUP BY (item->>'account_id')::BIGINT
    HAVING SUM((item->>'delta')::BIGINT) <> 0
  ) final_effects;
  IF v_final_entry_count < 2 THEN
    RAISE EXCEPTION 'Settlement batch requires at least two final net entries';
  END IF;$new$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO definition_text
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'earth_post_settlement_batch'
  LIMIT 1;
  IF definition_text IS NULL OR position(old_declaration IN definition_text) = 0 OR position(old_guard IN definition_text) = 0 THEN
    RAISE EXCEPTION 'Cannot harden earth_post_settlement_batch';
  END IF;
  definition_text := replace(definition_text, old_declaration, new_declaration);
  definition_text := replace(definition_text, old_guard, new_guard);
  EXECUTE definition_text;
END;
$$;
