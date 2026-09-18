-- EARTH ACTIVE MIGRATION: resolve the legacy output-column binding in the
-- atomic transaction result function without mutating migration 135.
-- PostgreSQL compiles PL/pgSQL lazily. This function-local setting makes the
-- historical unqualified `transaction_id` predicate resolve to the table
-- column, while preserving the public `(transaction_id, created)` contract.
ALTER FUNCTION earth_post_transaction(TEXT, BIGINT, INTEGER, TEXT, TEXT, TEXT, TEXT, JSONB)
  SET plpgsql.variable_conflict = 'use_column';
