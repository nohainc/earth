import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { getGlobalResourceAnalytics, getHouseResourceAnalytics } from './resource-analytics-postgres.ts';
import { getResourceBehaviorMetadata } from './resource-behavior-postgres.ts';

export async function handleEconomicRoutes(request: Request, env: Env, url: URL, viewer: { id: string }): Promise<Response | null> {
  if (url.pathname === '/api/economy/resources/metadata' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getResourceBehaviorMetadata(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/economy/resources' && request.method === 'GET') {
    const days = Math.min(90, Math.max(1, Number(url.searchParams.get('days') ?? 14) || 14));
    const result = await withRepository(env, async (repository) => ({ ownerId: viewer.id, days, resources: await getHouseResourceAnalytics(repository, viewer.id, days) }));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/economy/resources/global' && request.method === 'GET') {
    const days = Math.min(90, Math.max(1, Number(url.searchParams.get('days') ?? 14) || 14));
    const result = await withRepository(env, async (repository) => ({ days, resources: await getGlobalResourceAnalytics(repository, days) }));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if ((url.pathname === '/api/economy' || url.pathname === '/api/economy/balances') && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const accounts = await repository.query<{ account_id: string; asset_code: string; account_type: string; balance_units: string }>(`
        SELECT a.id AS account_id, assets.code AS asset_code,
               a.account_type,
               a.balance_units::TEXT AS balance_units
        FROM owner_registry o
        JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
        JOIN economic_assets assets ON assets.id = a.asset_id
        JOIN humans h ON h.house_id = o.id
        WHERE h.id = $1 AND o.owner_type = 'HOUSE' AND a.status = 'ACTIVE'
          AND ((assets.asset_kind = 'CREDIT' AND a.account_type = 'WALLET') OR (assets.asset_kind = 'RESOURCE' AND a.account_type = 'INVENTORY'))
        ORDER BY a.asset_id, a.id`, [viewer.id]);
      return { ownerId: viewer.id, assets: accounts.rows.map((row) => ({ code: row.asset_code, accountId: row.account_id, accountType: row.account_type, balance: row.balance_units })) };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/economy/transactions' && request.method === 'GET') {
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50) || 50));
    const beforeId = Number(url.searchParams.get('beforeId') ?? 0) || 0;
    const result = await withRepository(env, async (repository) => {
      const entries = await repository.query<{ transaction_id: string; correlation_id: string; game_day: number; game_minute: number; transaction_kind: string; asset_code: string; delta_units: string; entry_id: string }>(`
        SELECT t.id AS transaction_id, t.correlation_id, t.game_day, t.game_minute, t.transaction_kind,
               assets.code AS asset_code, e.delta_units::TEXT AS delta_units, e.id AS entry_id
        FROM economic_transactions t
        JOIN economic_entries e ON e.transaction_id = t.id
        JOIN economic_accounts a ON a.id = e.account_id
        JOIN economic_assets assets ON assets.id = a.asset_id
        JOIN humans h ON h.house_id = (SELECT id FROM owner_registry WHERE economic_id = a.owner_economic_id)
        WHERE h.id = $1
          AND ($2::BIGINT = 0 OR t.id < $2)
        ORDER BY t.game_day DESC, t.id DESC, e.id
        LIMIT $3`, [viewer.id, beforeId, limit * 8]);
      const grouped = new Map<string, Record<string, unknown>>();
      for (const row of entries.rows) {
        const entry = { id: row.entry_id, asset: row.asset_code, delta: row.delta_units, reason: row.transaction_kind };
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
