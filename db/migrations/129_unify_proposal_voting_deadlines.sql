-- A proposal has one authoritative voting window: opens_at plus the active
-- governance rule expressed by closes_game_day/closes_game_minute.  The
-- timestamp columns are compatibility/audit projections only; they must not
-- be allowed to disagree with the game-clock deadline.

-- Migration 089 accidentally seeded a 30-day period, contrary to Article 2.4
-- and the engine default of three game days.  Restrict this correction to the
-- generated baseline rules so institution-specific constitutional rules remain
-- untouched.
UPDATE governance_rules
SET voting_period_days = 3
WHERE name LIKE '% Governance Baseline'
  AND version = 1
  AND voting_period_days = 30;

-- Re-project every still-open legacy timestamp from its persisted game-clock
-- deadline.  At one real second per game minute this keeps compatibility
-- readers truthful while the engine continues to use only the game deadline.
WITH clock AS (
  SELECT ((game_day - 1) * 1440 + game_minute)::bigint AS current_minute
  FROM world_state
  WHERE id = 'WORLD'
)
UPDATE proposals p
SET closes_at = CURRENT_TIMESTAMP
    + (GREATEST(0, ((p.closes_game_day - 1) * 1440 + p.closes_game_minute) - clock.current_minute) * INTERVAL '1 second'),
    implementation_at = CASE
      WHEN p.implementation_game_day IS NULL THEN NULL
      ELSE CURRENT_TIMESTAMP
        + (GREATEST(0, ((p.implementation_game_day - 1) * 1440 + COALESCE(p.implementation_game_minute, 0)) - clock.current_minute) * INTERVAL '1 second')
    END
FROM clock
WHERE p.status = 'open'
  AND p.closes_game_day IS NOT NULL;
