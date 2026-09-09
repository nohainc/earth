-- `genesis_at` is the authoritative real timestamp. One elapsed real second
-- equals one game minute; scheduler-maintained day/minute values are not used
-- to determine voting windows.
WITH clock AS (
  SELECT GREATEST(0, floor(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - genesis_at))))::bigint AS current_minute
  FROM world_state
  WHERE id = 'WORLD'
), rebased AS (
  SELECT p.id,
    clock.current_minute AS opens_minute,
    clock.current_minute + COALESCE(r.voting_period_days, 3) * 1440 AS closes_minute
  FROM proposals p
  CROSS JOIN clock
  LEFT JOIN governance_rules r ON r.id = p.rule_version_id
  WHERE p.status = 'open'
)
UPDATE proposals p
SET opens_game_day = floor(rebased.opens_minute / 1440.0)::bigint + 1,
    opens_game_minute = mod(rebased.opens_minute, 1440)::integer,
    closes_game_day = floor(rebased.closes_minute / 1440.0)::bigint + 1,
    closes_game_minute = mod(rebased.closes_minute, 1440)::integer,
    opens_at = CURRENT_TIMESTAMP,
    closes_at = CURRENT_TIMESTAMP + ((rebased.closes_minute - rebased.opens_minute) * INTERVAL '1 second')
FROM rebased
WHERE p.id = rebased.id;
