-- Hybrid settlement: the Worker coordinates time and complex rules, while
-- PostgreSQL applies prepared, normal resource deltas set-wise and atomically.
CREATE OR REPLACE FUNCTION apply_prepared_daily_resource_profiles(p_game_day BIGINT)
RETURNS TABLE(applied_profiles INTEGER, deferred_profiles INTEGER)
LANGUAGE sql
AS $$
  WITH due AS (
    SELECT p.owner_id,
           p.energy_delta,
           p.food_delta,
           p.materials_delta,
           p.components_delta,
           p.compute_delta,
           GREATEST(1, p_game_day - p.last_settled_game_day)::NUMERIC AS elapsed_days
    FROM daily_settlement_profiles p
    WHERE p.status = 'clean'
      AND p.last_settled_game_day < p_game_day
      AND p.owner_kind IN ('human', 'city')
    FOR UPDATE
  ),
  eligible AS (
    SELECT d.*
    FROM due d
    WHERE NOT EXISTS (
      SELECT 1
      FROM (
        VALUES
          ('energy'::TEXT, d.energy_delta * d.elapsed_days),
          ('food'::TEXT, d.food_delta * d.elapsed_days),
          ('materials'::TEXT, d.materials_delta * d.elapsed_days),
          ('components'::TEXT, d.components_delta * d.elapsed_days),
          ('compute'::TEXT, d.compute_delta * d.elapsed_days)
      ) AS delta(resource, amount)
      LEFT JOIN resource_balances balance
        ON balance.owner_id = d.owner_id AND balance.resource = delta.resource
      WHERE delta.amount < 0
        AND COALESCE(balance.amount, 0) + delta.amount < 0
    )
  ),
  balance_updates AS (
    INSERT INTO resource_balances (owner_id, resource, amount)
    SELECT e.owner_id, delta.resource, delta.amount
    FROM eligible e
    CROSS JOIN LATERAL (
      VALUES
        ('energy'::TEXT, e.energy_delta * e.elapsed_days),
        ('food'::TEXT, e.food_delta * e.elapsed_days),
        ('materials'::TEXT, e.materials_delta * e.elapsed_days),
        ('components'::TEXT, e.components_delta * e.elapsed_days),
        ('compute'::TEXT, e.compute_delta * e.elapsed_days)
    ) AS delta(resource, amount)
    WHERE delta.amount <> 0
    ON CONFLICT (owner_id, resource) DO UPDATE
      SET amount = resource_balances.amount + EXCLUDED.amount
    RETURNING owner_id
  ),
  profile_updates AS (
    UPDATE daily_settlement_profiles profile
    SET last_settled_game_day = p_game_day,
        updated_at = CURRENT_TIMESTAMP
    FROM eligible e
    WHERE profile.owner_id = e.owner_id
      -- This dependency guarantees the balance writes execute before profiles
      -- are marked settled, even when all prepared deltas are zero.
      AND (SELECT COUNT(*) FROM balance_updates) >= 0
    RETURNING profile.owner_id
  ),
  run_updates AS (
    UPDATE daily_settlement_profile_runs run
    SET mode = 'applied'
    FROM profile_updates profile
    WHERE run.owner_id = profile.owner_id
      AND run.game_day = p_game_day
    RETURNING run.owner_id
  )
  SELECT
    (SELECT COUNT(*)::INTEGER FROM profile_updates),
    ((SELECT COUNT(*) FROM due) - (SELECT COUNT(*) FROM eligible))::INTEGER;
$$;

-- Version 075 introduced profiles after the world already existed. Treat each
-- existing profile as settled through the current game day, so the first run
-- of the elapsed-day function does not charge historical days retroactively.
UPDATE daily_settlement_profiles profile
SET last_settled_game_day = world.game_day,
    updated_at = CURRENT_TIMESTAMP
FROM world_state world
WHERE world.id = 'WORLD'
  AND profile.last_settled_game_day = 0;
