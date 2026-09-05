import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { currentHuman } from './auth-session.ts';
import {
  auditWorld as auditWorldPostgres,
  listCemeteryProfiles as listCemeteryProfilesPostgres,
  listEvents as listEventsPostgres,
  listHistory as listHistoryPostgres,
  listInstitutions as listInstitutionsPostgres,
  listMarketPriceHistory as listMarketPriceHistoryPostgres,
  listMembershipEvents as listMembershipEventsPostgres,
  listNotifications as listNotificationsPostgres,
  listOwnershipEvents as listOwnershipEventsPostgres,
  listPantheonOfAchievements as listPantheonOfAchievementsPostgres,
  listRankings as listRankingsPostgres,
  markAllNotificationsRead as markAllNotificationsReadPostgres,
  markNotificationRead as markNotificationReadPostgres,
} from './read-postgres.ts';

/**
 * Read-model routes: notifications, events, history, rankings, institutions,
 * audit, pantheon/cemetery, market history, admin email deliveries,
 * and world activity.
 *
 * These are all GET (or simple POST mark-read) routes that call read-only
 * projections from read-postgres.ts and related adapters.
 */
export async function handleReadModelRoutes(
  request: Request,
  env: Env,
  url: URL,
): Promise<Response | null> {

  // ── World activity ───────────────────────────────────────────────────────────
  if (url.pathname === '/api/world/activity' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, async (repository) => {
      const [world, technology] = await Promise.all([
        repository.query('SELECT game_day, market_batch_seconds FROM world_state WHERE id = $1', ['WORLD']),
        repository.query('SELECT progress FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewer.id]),
      ]);
      return {
        activity: [
          { type: 'world_clock', day: world.rows[0]?.game_day ?? 0 },
          { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 },
          { type: 'market_cycle', batch: world.rows[0]?.market_batch_seconds ?? 498 },
        ],
      };
    });
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  // ── Events / activity feed ───────────────────────────────────────────────────
  if (url.pathname === '/api/events' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const result = await withRepository(env, (repository) => listEventsPostgres(repository, viewer.id, limit));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  // ── Notifications ────────────────────────────────────────────────────────────
  if (url.pathname === '/api/notifications' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const result = await withRepository(env, (repository) => listNotificationsPostgres(repository, viewer.id, limit));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/notifications/read-all' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => markAllNotificationsReadPostgres(repository, viewer.id));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  const notificationReadMatch = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
  if (notificationReadMatch && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) =>
      markNotificationReadPostgres(repository, viewer.id, notificationReadMatch[1]),
    );
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  // ── History ──────────────────────────────────────────────────────────────────
  if (url.pathname === '/api/history' && request.method === 'GET') {
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const result = await withRepository(env, (repository) => listHistoryPostgres(repository, limit));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/ownership/events' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const result = await withRepository(env, (repository) => listOwnershipEventsPostgres(repository, viewer.id, limit));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/membership/events' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const result = await withRepository(env, (repository) => listMembershipEventsPostgres(repository, viewer.id, limit));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  // ── Public read models ───────────────────────────────────────────────────────
  if (url.pathname === '/api/institutions' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listInstitutionsPostgres(repository));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/rankings' && request.method === 'GET') {
    const category = url.searchParams.get('category') ?? undefined;
    const metric = url.searchParams.get('metric') ?? undefined;
    const search = url.searchParams.get('search') ?? undefined;
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
    const offset = Math.max(0, Number(url.searchParams.get('offset') ?? 0));
    const result = await withRepository(env, (repository) =>
      listRankingsPostgres(repository, { category, metric, search, limit, offset }),
    );
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if ((url.pathname === '/api/audit' || url.pathname === '/api/world/audit') && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => auditWorldPostgres(repository, viewer.id));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/pantheon' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listPantheonOfAchievementsPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Pantheon fetch failed' }, { status: 500 });
    }
  }

  if (url.pathname === '/api/cemetery' && request.method === 'GET') {
    const search = url.searchParams.get('search')?.trim();
    const dynasty = url.searchParams.get('dynasty')?.trim();
    const limit = Number(url.searchParams.get('limit') ?? 50);
    try {
      const result = await withRepository(env, (repository) =>
        listCemeteryProfilesPostgres(repository, { search, dynasty, limit }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Cemetery fetch failed' }, { status: 500 });
    }
  }

  if (url.pathname === '/api/market/history' && request.method === 'GET') {
    const product = url.searchParams.get('product')?.trim() ?? 'material';
    const days = Number(url.searchParams.get('days') ?? 30);
    try {
      const result = await withRepository(env, (repository) => listMarketPriceHistoryPostgres(repository, product, days));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market price history fetch failed' }, { status: 500 });
    }
  }

  return null; // Not a read-model route
}
