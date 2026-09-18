-- EARTH ACTIVE MIGRATION: require the immutable world epoch

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM world_state WHERE genesis_at IS NULL) THEN
    RAISE EXCEPTION 'world_state.genesis_at must be populated before migration 134';
  END IF;
END
$$;

ALTER TABLE world_state
  ALTER COLUMN genesis_at SET NOT NULL;
