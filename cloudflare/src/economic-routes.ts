import type { Env } from './index.ts';
import { withRepository } from './repository.ts';

function displayUnits(units: string | number, scale: string | number, decimals: string | number): string {
  return (Number(units) / Number(scale)).toFixed(Number(decimals));
}

export async function handleEconomicRoutes(request: Request, env: Env, url: URL, viewer: { id: string }): Promise<Response | null> {
  if ((url.pathname === '/api/economy' || url.pathname === '/api/economy/balances') && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const accounts = await repository.query<{ account_id: string; asset_code: string; account_type: string; balance_units: string; asset_scale: string; asset_decimals: string }>(`
        SELECT a.id AS account_id, assets.code AS asset_code,
               COALESCE(types.code, a.account_type::TEXT) AS account_type,
               a.balance AS balance_units,
               COALESCE(NULLIF(assets.scale, 0), assets.unit_scale) AS asset_scale,
               COALESCE(assets.decimals, CASE WHEN assets.id = 1 THEN 2 ELSE 6 END) AS asset_decimals
        FROM owner_registry o
        JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
        JOIN economic_assets assets ON assets.id = a.asset_id
        LEFT JOIN economic_account_types types ON types.id = a.account_type
        WHERE o.id = $1 AND a.status = 'active'
        ORDER BY a.asset_id, a.is_default_settlement DESC, a.id`, [viewer.id]);
      return { ownerId: viewer.id, assets: accounts.rows.map((row) => ({ code: row.asset_code, accountId: row.account_id, accountType: row.account_type, balance: displayUnits(row.balance_units, row.asset_scale, row.asset_decimals) })) };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/economy/transactions' && request.method === 'GET') {
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50) || 50));
    const beforeId = Number(url.searchParams.get('beforeId') ?? 0) || 0;
    const result = await withRepository(env, async (repository) => {
      const entries = await repository.query<{ transaction_id: string; correlation_id: string; game_day: number; game_minute: number; transaction_kind: string; reason_code: string; asset_code: string; asset_scale: string; asset_decimals: string; delta_units: string; entry_id: string }>(`
        SELECT t.id AS transaction_id, t.correlation_id, t.game_day, t.game_minute, t.transaction_kind,
               e.reason_code, assets.code AS asset_code,
               COALESCE(NULLIF(assets.scale, 0), assets.unit_scale) AS asset_scale,
               COALESCE(assets.decimals, CASE WHEN assets.id = 1 THEN 2 ELSE 6 END) AS asset_decimals,
               e.delta AS delta_units, e.id AS entry_id
        FROM economic_transactions t
        JOIN economic_entries e ON e.transaction_id = t.id
        JOIN economic_accounts a ON a.id = e.account_id
        JOIN economic_assets assets ON assets.id = a.asset_id
        WHERE a.owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)
          AND ($2::BIGINT = 0 OR t.id < $2)
        ORDER BY t.game_day DESC, t.id DESC, e.id
        LIMIT $3`, [viewer.id, beforeId, limit * 8]);
      const grouped = new Map<string, Record<string, unknown>>();
      for (const row of entries.rows) {
        const entry = { id: row.entry_id, asset: row.asset_code, delta: displayUnits(row.delta_units, row.asset_scale, row.asset_decimals), reason: row.reason_code };
        const transaction = grouped.get(row.transaction_id);
        if (transaction) (transaction.entries as unknown[]).push(entry);
        else if (grouped.size < limit) grouped.set(row.transaction_id, { id: row.transaction_id, correlationId: row.correlation_id, gameDay: row.game_day, gameMinute: row.game_minute, kind: row.transaction_kind, entries: [entry] });
      }
      return { transactions: [...grouped.values()] };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  return null;
}
