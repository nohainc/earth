-- A proposal resolved between the earlier rebase migrations can retain an
-- implementation deadline from the retired scheduler clock. Repair only
-- passed, unexecuted proposals whose stored implementation predates voting
-- close; do not change their outcome or execution status.
UPDATE proposals p
SET implementation_game_day = floor(((((p.closes_game_day - 1) * 1440 + p.closes_game_minute)
      + COALESCE(p.implementation_delay_days, 0) * 1440) / 1440.0))::bigint + 1,
    implementation_game_minute = mod(((p.closes_game_day - 1) * 1440 + p.closes_game_minute)
      + COALESCE(p.implementation_delay_days, 0) * 1440, 1440)::integer,
    implementation_at = p.closes_at + (COALESCE(p.implementation_delay_days, 0) * 1440 * INTERVAL '1 second')
WHERE p.outcome = 'passed'
  AND p.executed_at IS NULL
  AND p.implementation_game_day < p.closes_game_day;
