import type { PostgresRepository } from './repository.ts';

type ShadowRow = {
  economic_id: string;
  owner_id: string;
  asset_id: number;
  legacy_units: string;
  v2_units: string;
};

/**
 * Economy V2 migration evidence. Legacy tables are discovered dynamically so
 * the clean baseline can run the scheduler before compatibility tables exist.
 * No function in this module writes to an economic account or balance table.
 */
async function legacyTablesAvailable(repository: PostgresRepository): Promise<boolean> {
  const result = await repository.query<{ available: boolean }>(
    `SELECT to_regclass('public.account_balances') IS NOT NULL
          AND to_regclass('public.resource_balances') IS NOT NULL AS available`,
  );
  return Boolean(result.rows[0]?.available);
}

function snapshotSql(includeLegacy: boolean): string {
  if (!includeLegacy) {
    return `SELECT o.economic_id, o.id AS owner_id,
             a.id AS asset_id, 0::BIGINT AS legacy_units,
             COALESCE(SUM(ea.balance_units), 0)::BIGINT AS v2_units
        FROM owner_registry o
        CROSS JOIN economic_assets a
        LEFT JOIN economic_accounts ea
          ON ea.owner_economic_id = o.economic_id
         AND ea.asset_id = a.id
         AND ea.status = 'ACTIVE'
       GROUP BY o.economic_id, o.id, a.id
       ORDER BY o.economic_id, a.id`;
  }

  // These identifiers are interpolated only after to_regclass confirmed both
  // compatibility tables exist. The legacy schema is intentionally isolated
  // from the clean baseline and never participates in settlement decisions.
  return `WITH legacy AS (
      SELECT o.economic_id, o.id AS owner_id, 1 AS asset_id,
             ROUND(COALESCE(SUM(ab.balance), 0) * 100)::BIGINT AS units
        FROM owner_registry o LEFT JOIN account_balances ab ON ab.owner_id = o.id AND ab.currency = 'CREDIT'
       GROUP BY o.economic_id, o.id
      UNION ALL
      SELECT o.economic_id, o.id, a.id,
             ROUND(COALESCE(SUM(rb.amount), 0) * 1000000)::BIGINT
        FROM owner_registry o CROSS JOIN economic_assets a
        LEFT JOIN resource_balances rb ON rb.owner_id = o.id AND UPPER(rb.resource) = a.code
       WHERE a.id > 1
       GROUP BY o.economic_id, o.id, a.id
    ), v2 AS (
      SELECT o.economic_id, o.id AS owner_id, a.id AS asset_id,
             COALESCE(SUM(ea.balance_units), 0)::BIGINT AS units
        FROM owner_registry o CROSS JOIN economic_assets a
        LEFT JOIN economic_accounts ea ON ea.owner_economic_id = o.economic_id
         AND ea.asset_id = a.id AND ea.status = 'ACTIVE'
       GROUP BY o.economic_id, o.id, a.id
    )
    SELECT l.economic_id, l.owner_id, l.asset_id, l.units AS legacy_units,
           COALESCE(v.units, 0)::BIGINT AS v2_units
     FROM legacy l LEFT JOIN v2 v ON v.economic_id = l.economic_id AND v.asset_id = l.asset_id
     ORDER BY l.economic_id, l.asset_id`;
}

export async function captureEconomyShadowOpening(repository: PostgresRepository, day: number): Promise<void> {
  const includeLegacy = await legacyTablesAvailable(repository);
  await repository.query(
    `INSERT INTO economy_shadow_openings
       (game_day, owner_economic_id, owner_id, asset_id, legacy_units, v2_units)
     SELECT $1, snapshot.economic_id, snapshot.owner_id, snapshot.asset_id,
            snapshot.legacy_units, snapshot.v2_units
       FROM (${snapshotSql(includeLegacy)}) AS snapshot
     ON CONFLICT (game_day, owner_economic_id, asset_id) DO NOTHING`,
    [day],
  );
  await repository.query(
    `INSERT INTO economy_shadow_runs (game_day, status, started_at)
     VALUES ($1, $2, CURRENT_TIMESTAMP)
     ON CONFLICT (game_day) DO UPDATE SET status = EXCLUDED.status, error_message = NULL`,
    [day, includeLegacy ? 'captured' : 'skipped'],
  );
}

export async function reconcileEconomyShadowDay(repository: PostgresRepository, day: number): Promise<void> {
  const run = (await repository.query<{ status: string }>('SELECT status FROM economy_shadow_runs WHERE game_day = $1', [day])).rows[0];
  if (!run || run.status === 'skipped') return;
  if (!await legacyTablesAvailable(repository)) return;
  await repository.query(
    `WITH closing AS (${snapshotSql(true)}), written AS (
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
        reconciled_at = CURRENT_TIMESTAMP
      RETURNING 1
    )
    UPDATE economy_shadow_runs r SET status = 'reconciled',
       owners_checked = s.owners_checked, assets_checked = s.assets_checked,
       differences = s.differences, absolute_difference_units = s.absolute_difference_units,
       unexplained_difference = s.differences > 0, completed_at = CURRENT_TIMESTAMP
      FROM (SELECT COUNT(DISTINCT owner_economic_id) AS owners_checked,
                   COUNT(*) AS assets_checked,
                   COUNT(*) FILTER (WHERE difference_kind <> 'none') AS differences,
                   COALESCE(SUM(ABS(difference_units)), 0) AS absolute_difference_units
              FROM economy_shadow_reconciliations WHERE game_day = $1) s
     WHERE r.game_day = $1`,
    [day],
  );
}
