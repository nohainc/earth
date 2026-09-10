import type { PostgresRepository } from './repository.ts';

const snapshotQuery = `
  WITH legacy AS (
    SELECT o.economic_id, o.id AS owner_id, 1::SMALLINT AS asset_id,
           ROUND(COALESCE(SUM(ab.balance), 0) * 100)::BIGINT AS units
      FROM owner_registry o LEFT JOIN account_balances ab
        ON ab.owner_id = o.id AND ab.currency = 'CREDIT'
     GROUP BY o.economic_id, o.id
    UNION ALL
    SELECT o.economic_id, o.id, a.id,
           ROUND(COALESCE(SUM(rb.amount), 0) * 1000000)::BIGINT
      FROM owner_registry o CROSS JOIN economic_assets a
      LEFT JOIN resource_balances rb ON rb.owner_id = o.id AND UPPER(rb.resource) = a.code
     WHERE a.id > 1
     GROUP BY o.economic_id, o.id, a.id
  ), v2 AS (
    SELECT o.economic_id, o.id AS owner_id, assets.id AS asset_id, COALESCE(SUM(a.balance), 0)::BIGINT AS units
      FROM owner_registry o CROSS JOIN economic_assets assets
      LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
        AND a.asset_id = assets.id AND a.is_default_settlement AND a.status = 'active'
     GROUP BY o.economic_id, o.id, assets.id
  )
  SELECT l.economic_id, l.owner_id, l.asset_id, l.units AS legacy_units,
         COALESCE(v.units, 0)::BIGINT AS v2_units
    FROM legacy l LEFT JOIN v2 v ON v.economic_id = l.economic_id AND v.asset_id = l.asset_id`;

export async function captureEconomyShadowOpening(repository: PostgresRepository, day: number): Promise<void> {
  await repository.query(
    `INSERT INTO economy_shadow_openings (game_day, owner_economic_id, owner_id, asset_id, legacy_units, v2_units)
     SELECT $1, snapshot.economic_id, snapshot.owner_id, snapshot.asset_id,
            snapshot.legacy_units, snapshot.v2_units
       FROM (${snapshotQuery}) AS snapshot
     ON CONFLICT (game_day, owner_economic_id, asset_id) DO NOTHING`,
    [day],
  );
  await repository.query(
    `INSERT INTO economy_shadow_runs (game_day, status, started_at)
     VALUES ($1, 'captured', CURRENT_TIMESTAMP)
     ON CONFLICT (game_day) DO UPDATE SET status = 'captured', error_message = NULL`,
    [day],
  );
}

export async function reconcileEconomyShadowDay(repository: PostgresRepository, day: number): Promise<void> {
  await repository.query(
    `WITH closing AS (${snapshotQuery})
     INSERT INTO economy_shadow_reconciliations
       (game_day, owner_economic_id, owner_id, asset_id,
        legacy_opening_units, v2_opening_units, legacy_closing_units, v2_closing_units,
        legacy_delta_units, v2_delta_units, difference_units, difference_kind, details)
     SELECT $1, o.owner_economic_id, o.owner_id, o.asset_id,
            o.legacy_units, o.v2_units, c.legacy_units, c.v2_units,
            c.legacy_units - o.legacy_units, c.v2_units - o.v2_units,
            (c.v2_units - o.v2_units) - (c.legacy_units - o.legacy_units),
            CASE WHEN c.v2_units <> c.legacy_units THEN 'balance'
                 WHEN (c.v2_units - o.v2_units) <> (c.legacy_units - o.legacy_units) THEN 'delta'
                 ELSE 'none' END,
            jsonb_build_object('legacyClosing', c.legacy_units, 'v2Closing', c.v2_units)
       FROM economy_shadow_openings o
       JOIN closing c ON c.economic_id = o.owner_economic_id AND c.asset_id = o.asset_id
      WHERE o.game_day = $1
     ON CONFLICT (game_day, owner_economic_id, asset_id) DO UPDATE SET
       legacy_closing_units = EXCLUDED.legacy_closing_units,
       v2_closing_units = EXCLUDED.v2_closing_units,
       legacy_delta_units = EXCLUDED.legacy_delta_units,
       v2_delta_units = EXCLUDED.v2_delta_units,
       difference_units = EXCLUDED.difference_units,
       difference_kind = EXCLUDED.difference_kind,
       details = EXCLUDED.details,
       reconciled_at = CURRENT_TIMESTAMP`,
    [day],
  );
  await repository.query(
    `INSERT INTO economy_shadow_runs
       (game_day, status, owners_checked, assets_checked, differences, absolute_difference_units, unexplained_difference, completed_at)
     SELECT $1, 'reconciled', COUNT(DISTINCT owner_economic_id), COUNT(*),
            COUNT(*) FILTER (WHERE difference_kind <> 'none'),
            COALESCE(SUM(ABS(difference_units)), 0),
            COUNT(*) FILTER (WHERE difference_kind <> 'none') > 0,
            CURRENT_TIMESTAMP
       FROM economy_shadow_reconciliations WHERE game_day = $1
     ON CONFLICT (game_day) DO UPDATE SET
       status = EXCLUDED.status, owners_checked = EXCLUDED.owners_checked,
       assets_checked = EXCLUDED.assets_checked, differences = EXCLUDED.differences,
       absolute_difference_units = EXCLUDED.absolute_difference_units,
       unexplained_difference = EXCLUDED.unexplained_difference,
       completed_at = EXCLUDED.completed_at`,
    [day],
  );
}
