import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  getDynastyOverview,
  unlockDynastyPerk,
  equipDynastyHeirloom,
  forgeDynastyHeirloom,
  setDynastyMotto,
} from './dynasty-postgres.ts';

export async function handleDynastyRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string; email?: string; name?: string },
): Promise<Response | null> {
  if (url.pathname === '/api/dynasty' && request.method === 'GET') {
    const email = viewer.email || 'amara@earth.local';
    const humanId = viewer.id || 'H-0044';
    const humanName = viewer.name || 'Amara Vance';
    const result = await withRepository(env, (repository) => getDynastyOverview(repository, email, humanId, humanName));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/dynasty/perks/unlock' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ perkKey?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const perkKey = parsed.value.perkKey?.trim() ?? '';
    if (!perkKey) return Response.json({ ok: false, error: 'Perk key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        unlockDynastyPerk(repository, viewer.email || 'amara@earth.local', perkKey, 1, resolveIdempotencyKey(request, parsed.value.correlationId)),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Perk unlock failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if (url.pathname === '/api/dynasty/heirlooms/equip' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ heirloomId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const heirloomId = parsed.value.heirloomId?.trim() ?? '';
    if (!heirloomId) return Response.json({ ok: false, error: 'Heirloom ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        equipDynastyHeirloom(repository, viewer.email || 'amara@earth.local', heirloomId, viewer.id, resolveIdempotencyKey(request, parsed.value.correlationId)),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Equip failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if (url.pathname === '/api/dynasty/heirlooms/forge' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; heirloomType?: string; inscription?: string; statBuff?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const name = parsed.value.name?.trim() ?? '';
    const heirloomType = parsed.value.heirloomType?.trim() ?? 'dynasty_standard';
    const inscription = parsed.value.inscription?.trim() ?? 'Forged by the house patriarch.';
    const statBuff = parsed.value.statBuff?.trim() ?? '+5% Prestige & Influence';
    if (!name) return Response.json({ ok: false, error: 'Heirloom name is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        forgeDynastyHeirloom(repository, viewer.email || 'amara@earth.local', name, heirloomType, inscription, statBuff, resolveIdempotencyKey(request, parsed.value.correlationId)),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Heirloom forge failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if (url.pathname === '/api/dynasty/motto' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ motto?: string; dynastyName?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const motto = parsed.value.motto?.trim() ?? '';
    const dynastyName = parsed.value.dynastyName?.trim();
    if (!motto) return Response.json({ ok: false, error: 'Motto is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setDynastyMotto(repository, viewer.email || 'amara@earth.local', motto, dynastyName, resolveIdempotencyKey(request, parsed.value.correlationId)),
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
