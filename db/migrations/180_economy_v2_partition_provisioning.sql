-- Economy V2 Plan 37: keep high-volume entry partitions ahead of the clock.

CREATE TABLE IF NOT EXISTS economic_entry_partitions (
  from_game_day BIGINT PRIMARY KEY,
  to_game_day BIGINT NOT NULL UNIQUE,
  partition_name TEXT NOT NULL UNIQUE,
  provisioned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO economic_entry_partitions (from_game_day, to_game_day, partition_name)
VALUES
  (0, 1001, 'economic_entries_days_0000_1000'),
  (1001, 2001, 'economic_entries_days_1001_2000'),
  (2001, 3001, 'economic_entries_days_2001_3000')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION earth_provision_economic_entry_partitions(
  p_game_day BIGINT,
  p_ranges_ahead INTEGER DEFAULT 5
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  next_from BIGINT;
  next_to BIGINT;
  target_to BIGINT;
  partition_name TEXT;
  provisioned INTEGER := 0;
  default_present BOOLEAN;
BEGIN
  IF p_game_day < 0 OR p_ranges_ahead < 1 THEN
    RAISE EXCEPTION 'Invalid economic entry partition provisioning arguments';
  END IF;

  SELECT COALESCE(MAX(to_game_day), 3001)
    INTO next_from
    FROM economic_entry_partitions;
  target_to := p_game_day + (p_ranges_ahead * 1000) + 1;

  WHILE next_from < target_to LOOP
    next_to := next_from + 1000;
    partition_name := format('economic_entries_days_%s_%s',
      lpad(next_from::TEXT, 4, '0'), lpad((next_to - 1)::TEXT, 4, '0'));
    default_present := to_regclass('economic_entries_default') IS NOT NULL;

    -- A default partition must be detached before a new range can be added;
    -- this also lets us re-home rows that arrived there before provisioning.
    IF default_present THEN
      ALTER TABLE economic_entries DETACH PARTITION economic_entries_default;
    END IF;

    EXECUTE format(
      'CREATE TABLE %I PARTITION OF economic_entries FOR VALUES FROM (%s) TO (%s)',
      partition_name, next_from, next_to
    );

    IF default_present THEN
      EXECUTE format(
        'INSERT INTO %I SELECT * FROM economic_entries_default WHERE game_day >= %s AND game_day < %s',
        partition_name, next_from, next_to
      );
      EXECUTE format(
        'DELETE FROM economic_entries_default WHERE game_day >= %s AND game_day < %s',
        next_from, next_to
      );
      ALTER TABLE economic_entries ATTACH PARTITION economic_entries_default DEFAULT;
    END IF;

    -- Migration 171 installs the deferred balance trigger on each leaf.
    EXECUTE format('DROP TRIGGER IF EXISTS economic_entries_balance_check ON %I', partition_name);
    EXECUTE format(
      'CREATE CONSTRAINT TRIGGER economic_entries_balance_check
       AFTER INSERT OR UPDATE OR DELETE ON %I
       DEFERRABLE INITIALLY DEFERRED
       FOR EACH ROW
       EXECUTE FUNCTION earth_assert_economic_transaction_balanced()',
      partition_name
    );

    INSERT INTO economic_entry_partitions (from_game_day, to_game_day, partition_name)
    VALUES (next_from, next_to, partition_name)
    ON CONFLICT DO NOTHING;
    provisioned := provisioned + 1;
    next_from := next_to;
  END LOOP;

  RETURN provisioned;
END;
$$;

