-- Rebase implementation windows of proposals that were open while the
-- scheduler clock was still used. The implementation delay begins after the
-- same genesis-derived voting end used by the resolver.
UPDATE proposals p
SET implementation_game_day = floor(((((p.closes_game_day - 1) * 1440 + p.closes_game_minute)
      + COALESCE(p.implementation_delay_days, 0) * 1440) / 1440.0))::bigint + 1,
    implementation_game_minute = mod(((p.closes_game_day - 1) * 1440 + p.closes_game_minute)
      + COALESCE(p.implementation_delay_days, 0) * 1440, 1440)::integer,
    implementation_at = p.closes_at + (COALESCE(p.implementation_delay_days, 0) * 1440 * INTERVAL '1 second')
WHERE p.status = 'open'
  AND p.closes_game_day IS NOT NULL;
