-- EARTH ACTIVE MIGRATION: finalize the atomic transaction result contract

-- Migration 135 already uses explicit table qualification for the
-- economic_entries transaction_id lookup. No session or function-level
-- plpgsql.variable_conflict setting is required. Such settings require
-- elevated PostgreSQL privileges and must not be part of an application
-- migration. Keep this forward migration as an explicit, privilege-free
-- reconciliation marker for environments that have applied 135.
DO $$
BEGIN
  PERFORM 1
    FROM pg_proc
   WHERE proname = 'earth_post_transaction'
     AND pg_get_function_identity_arguments(oid) = 'p_correlation_id text, p_game_day bigint, p_game_minute integer, p_transaction_kind text, p_source_type text, p_source_id text, p_rules_version text, p_entries jsonb';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'earth_post_transaction atomic result function is missing';
  END IF;
END;
$$;
