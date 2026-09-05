import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { currentHuman } from './auth-session.ts';
import {
  getHouseOverview,
  unlockHousePerk,
  equipHouseHeirloom,
  forgeHouseHeirloom,
  updateHouseMotto,
} from './house-postgres.ts';

/**
 * Canonical routes for the generational house system.
 */
export async function handleHouseRoutes(
  request: Request,
  env: Env,
  url: URL,
): Promise<Response | null> {

  const isHousePath = url.pathname.startsWith('/api/house');
  if (!isHousePath) return null;

  // GET /api/house — overview of lineage, perks, and heirlooms
  if (url.pathname === '/api/house' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getHouseOverview(repository, viewer.email, viewer.id, viewer.display_name));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'House overview could not be loaded';
      return Response.json({ ok: false, error: message }, { status: /not found|account/i.test(message) ? 404 : 400 });
    }
  }

  // POST /api/house/perks/unlock
  if (
    url.pathname === '/api/house/perks/unlock' &&
    request.method === 'POST'
  ) {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ perkKey?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const perkKey = parsed.value.perkKey?.trim() ?? '';
    if (!perkKey) return Response.json({ ok: false, error: 'Perk key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        unlockHousePerk(repository, viewer.email || 'amara@earth.local', perkKey, 1, resolveIdempotencyKey(request, parsed.value.correlationId)),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Perk unlock failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  // POST /api/house/heirlooms/equip
  if (
    url.pathname === '/api/house/heirlooms/equip' &&
    request.method === 'POST'
  ) {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ heirloomId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const heirloomId = parsed.value.heirloomId?.trim() ?? '';
    if (!heirloomId) return Response.json({ ok: false, error: 'Heirloom ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        equipHouseHeirloom(
          repository,
          viewer.email || 'amara@earth.local',
          heirloomId,
          viewer.id,
          resolveIdempotencyKey(request, parsed.value.correlationId),
        ),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Equip failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  // POST /api/house/heirlooms/forge
  if (
    url.pathname === '/api/house/heirlooms/forge' &&
    request.method === 'POST'
  ) {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{
      name?: string;
      heirloomType?: string;
      inscription?: string;
      statBuff?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const name = parsed.value.name?.trim() ?? '';
    const heirloomType = parsed.value.heirloomType?.trim() ?? 'house_standard';
    const inscription = parsed.value.inscription?.trim() ?? 'Forged by the house patriarch.';
    const statBuff = parsed.value.statBuff?.trim() ?? '+5% Prestige & Influence';
    if (!name) return Response.json({ ok: false, error: 'Heirloom name is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        forgeHouseHeirloom(
          repository,
          viewer.email || 'amara@earth.local',
          name,
          heirloomType,
          inscription,
          statBuff,
          resolveIdempotencyKey(request, parsed.value.correlationId),
        ),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Heirloom forge failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  // POST /api/house/motto
  if (
    url.pathname === '/api/house/motto' &&
    request.method === 'POST'
  ) {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ motto?: string; houseName?: string; dynastyName?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const motto = parsed.value.motto?.trim() ?? '';
    const houseName = parsed.value.houseName?.trim() ?? parsed.value.dynastyName?.trim();
    if (houseName !== undefined && houseName.length < 2) {
      return Response.json({ ok: false, error: 'House name must be at least 2 characters' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        updateHouseMotto(
          repository,
          viewer.email || 'amara@earth.local',
          motto,
          houseName,
          resolveIdempotencyKey(request, parsed.value.correlationId),
        ),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Motto update failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  return null;
}
