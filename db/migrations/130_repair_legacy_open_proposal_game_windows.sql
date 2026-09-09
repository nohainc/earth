-- Repair open proposals created before the proposal engine used the persisted
-- scheduler clock. Their stored deadline was calculated from a separate
-- genesis-derived clock and can be hundreds of game days in the future.

ALTER TABLE proposals ADD COLUMN IF NOT EXISTS opens_game_day BIGINT;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS opens_game_minute INTEGER;
ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_opens_game_minute_check;
ALTER TABLE proposals ADD CONSTRAINT proposals_opens_game_minute_check CHECK (opens_game_minute BETWEEN 0 AND 1439);

WITH clock AS (
  SELECT ((game_day - 1) * 1440 + game_minute)::bigint AS current_minute
  FROM world_state
  WHERE id = 'WORLD'
), repaired AS (
  SELECT p.id,
    clock.current_minute AS opens_minute,
    clock.current_minute + COALESCE(r.voting_period_days, 3) * 1440 AS closes_minute
  FROM proposals p
  CROSS JOIN clock
  LEFT JOIN governance_rules r ON r.id = p.rule_version_id
  WHERE p.status = 'open'
    AND p.opens_game_day IS NULL
)
UPDATE proposals p
SET opens_game_day = floor(repaired.opens_minute / 1440.0)::bigint + 1,
    opens_game_minute = mod(repaired.opens_minute, 1440)::integer,
    closes_game_day = floor(repaired.closes_minute / 1440.0)::bigint + 1,
    closes_game_minute = mod(repaired.closes_minute, 1440)::integer,
    closes_at = CURRENT_TIMESTAMP + ((repaired.closes_minute - repaired.opens_minute) * INTERVAL '1 second')
FROM repaired
WHERE p.id = repaired.id;
