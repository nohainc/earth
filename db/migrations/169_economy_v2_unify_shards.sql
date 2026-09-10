-- Economy V2 Plan 20: one bounded shard topology and canonical mapping.

ALTER TABLE daily_settlement_runs
  DROP CONSTRAINT IF EXISTS daily_settlement_runs_shard_count_check,
  ADD CONSTRAINT daily_settlement_runs_shard_count_check CHECK (shard_count BETWEEN 1 AND 64);

CREATE OR REPLACE FUNCTION earth_settlement_shard(
  p_owner_economic_id BIGINT,
  p_shard_count INTEGER
)
RETURNS SMALLINT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_owner_economic_id IS NULL OR p_shard_count IS NULL OR p_shard_count < 1 OR p_shard_count > 64 THEN
    RAISE EXCEPTION 'Settlement shard mapping requires a valid owner ID and shard count <= 64';
  END IF;
  RETURN mod(p_owner_economic_id, p_shard_count)::SMALLINT;
END;
$$;

CREATE OR REPLACE FUNCTION earth_sync_settlement_profile_shard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.owner_economic_id IS NULL THEN
    SELECT economic_id INTO NEW.owner_economic_id
    FROM owner_registry WHERE id = NEW.owner_id;
  END IF;
  IF NEW.owner_economic_id IS NULL THEN
    RAISE EXCEPTION 'Settlement profile owner % has no economic ID', NEW.owner_id;
  END IF;
  NEW.shard := earth_settlement_shard(NEW.owner_economic_id, 64);
  RETURN NEW;
END;
$$;

UPDATE daily_settlement_profiles p
SET owner_economic_id = o.economic_id,
    shard = earth_settlement_shard(o.economic_id, 64)
FROM owner_registry o
WHERE o.id = p.owner_id;

DROP TRIGGER IF EXISTS daily_settlement_profile_shard_sync ON daily_settlement_profiles;
CREATE TRIGGER daily_settlement_profile_shard_sync
BEFORE INSERT OR UPDATE OF owner_id, owner_economic_id ON daily_settlement_profiles
FOR EACH ROW
EXECUTE FUNCTION earth_sync_settlement_profile_shard();
