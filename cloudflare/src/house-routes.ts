import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { currentHuman } from './auth-session.ts';
import {
  getHouseProfile,
  updateHouseProfile,
} from './house-postgres.ts';
import { getHouseDailySummary } from './house-daily-summary-postgres.ts';
import { getHouseAutomation, previewHouseAutomation, saveHouseAutomation } from './house-policy-postgres.ts';
import { advanceHouseOnboarding, getHouseOnboarding } from './house-onboarding-postgres.ts';
import { getHouseResidency, moveHouseResidence, quoteHouseMove } from './residency-postgres.ts';
import { claimHouseEntrySupport, getHouseEntrySupport } from './catch-up-postgres.ts';
import { getHouseCatchUpTargets } from './catch-up-targets-postgres.ts';
import { registerSuccessor as registerSuccessorPostgres } from './lifecycle-postgres.ts';

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

  if (
    request.method === 'POST' &&
    (url.pathname === '/api/house/perks/unlock' ||
      url.pathname === '/api/house/heirlooms/equip' ||
      url.pathname === '/api/house/heirlooms/forge')
  ) {
    return Response.json(
      {
        ok: false,
        error: 'House perks and heirlooms are retired in V5 and are not available.',
      },
      { status: 410 },
    );
  }

  if (url.pathname === '/api/house/catch-up-targets' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => getHouseCatchUpTargets(repository, viewer.houseId));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json(result);
  }

  if (url.pathname === '/api/house/residency' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => getHouseResidency(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/house/residency/quote' && request.method === 'GET') {
    return Response.json({ ok: false, error: 'Territory-specific residence moves are retired in V5; House capacity is pooled.' }, { status: 410 });
    /* istanbul ignore next -- retained below for historical/admin callers. */
    const viewer = await currentHuman(request, env);
    const territoryId = url.searchParams.get('territoryId')?.trim();
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    if (!territoryId) return Response.json({ ok: false, error: 'territoryId is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => quoteHouseMove(repository, viewer.id, territoryId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Residence quote unavailable' }, { status: 409 }); }
  }

  if (url.pathname === '/api/house/residency/move' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Territory-specific residence moves are retired in V5; House capacity is pooled.' }, { status: 410 });
    /* istanbul ignore next -- retained below for historical/admin callers. */
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ territoryId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const territoryId = parsed.value.territoryId?.trim();
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!territoryId || !correlationId) return Response.json({ ok: false, error: 'territoryId and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => moveHouseResidence(repository, { humanId: viewer.id, territoryId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Residence move failed' }, { status: 409 }); }
  }

  if (url.pathname === '/api/house/onboarding' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => getHouseOnboarding(repository, viewer.house_id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/house/succession' && request.method === 'POST') {
    const viewer = await currentHuman(request, env, true);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ name?: string }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, {
        humanId: viewer.id,
        successorName: (parsed.value.name ?? '').trim(),
        currentLifeStatus: viewer.life_status,
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Succession plan failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/house/onboarding/advance' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ milestone?: string; expertSkip?: boolean; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) => advanceHouseOnboarding(repository, viewer.house_id, parsed.value.milestone, parsed.value.expertSkip === true, resolveIdempotencyKey(request, parsed.value.correlationId)));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Onboarding update failed' }, { status: 400 });
    }
  }

  if (url.pathname === '/api/house/entry-opportunities' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getHouseEntrySupport(repository, viewer.house_id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Entry opportunities unavailable' }, { status: 400 }); }
  }

  if (url.pathname === '/api/house/entry-support/claim' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => claimHouseEntrySupport(repository, viewer.house_id, correlationId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Entry support claim failed' }, { status: 409 }); }
  }

  if (url.pathname === '/api/house/daily-summary' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const rawDay = url.searchParams.get('day');
    const requestedDay = rawDay == null ? undefined : Number(rawDay);
    if (rawDay != null && (!Number.isInteger(requestedDay) || requestedDay < 0)) {
      return Response.json({ ok: false, error: 'day must be a non-negative integer' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) => getHouseDailySummary(repository, viewer.house_id, requestedDay));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Daily summary could not be loaded';
      return Response.json({ ok: false, error: message }, { status: /unavailable/i.test(message) ? 503 : 400 });
    }
  }

  if (url.pathname === '/api/house/policies' && request.method === 'GET') {
    return Response.json({ ok: false, error: 'House policy rows are deprecated; use /api/house/automation' }, { status: 410 });
  }

  if (url.pathname === '/api/house/policies' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'House policy rows are deprecated; use /api/house/automation' }, { status: 410 });
  }

  if (url.pathname === '/api/house/automation' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getHouseAutomation(repository, viewer.house_id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Automation read failed' }, { status: 400 });
    }
  }

  if (url.pathname === '/api/house/automation' && request.method === 'PUT') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<Record<string, unknown>>(request);
    if (!parsed.ok) return parsed.response;
    const value = parsed.value;
    try {
      const result = await withRepository(env, (repository) => saveHouseAutomation(repository, viewer.house_id, {
        enabled: value.enabled !== false,
        effectiveFromGameDay: value.effectiveFromGameDay == null ? undefined : Number(value.effectiveFromGameDay), dailySpendCap: String(value.dailySpendCap ?? '0'),
        minimumReserve: (value.minimumReserve ?? {}) as Record<string, string | number>, sellAbove: (value.sellAbove ?? {}) as Record<string, string | number>, maxInputPrice: (value.maxInputPrice ?? {}) as Record<string, string | number>, minSalePrice: (value.minSalePrice ?? {}) as Record<string, string | number>, maxBuyQuantity: (value.maxBuyQuantity ?? {}) as Record<string, string | number>, maxSellQuantity: (value.maxSellQuantity ?? {}) as Record<string, string | number>, correlationId: resolveIdempotencyKey(request, String(value.correlationId ?? '')),
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Automation save failed' }, { status: 400 });
    }
  }

  if (url.pathname === '/api/house/automation/preview' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<Record<string, unknown>>(request);
    if (!parsed.ok) return parsed.response;
    const value = parsed.value;
    try {
      const result = await withRepository(env, (repository) => previewHouseAutomation(repository, viewer.house_id, {
        enabled: value.enabled !== false,
        dailySpendCap: String(value.dailySpendCap ?? '0'),
        minimumReserve: (value.minimumReserve ?? {}) as Record<string, string | number>,
        sellAbove: (value.sellAbove ?? {}) as Record<string, string | number>,
        maxInputPrice: (value.maxInputPrice ?? {}) as Record<string, string | number>,
        minSalePrice: (value.minSalePrice ?? {}) as Record<string, string | number>,
        maxBuyQuantity: (value.maxBuyQuantity ?? {}) as Record<string, string | number>,
        maxSellQuantity: (value.maxSellQuantity ?? {}) as Record<string, string | number>,
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Automation preview failed' }, { status: 400 });
    }
  }

  // GET /api/house — canonical House identity, succession, and lineage
  if (url.pathname === '/api/house' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getHouseProfile(repository, viewer.house_id, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'House overview could not be loaded';
      return Response.json({ ok: false, error: message }, { status: /not found|account/i.test(message) ? 404 : 400 });
    }
  }

  // PATCH /api/house/profile
  if (
    url.pathname === '/api/house/profile' &&
    request.method === 'PATCH'
  ) {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ motto?: string; houseName?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const motto = parsed.value.motto?.trim() ?? '';
    const houseName = parsed.value.houseName?.trim();
    if (houseName !== undefined && houseName.length < 2) {
      return Response.json({ ok: false, error: 'House name must be at least 2 characters' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        updateHouseProfile(repository, viewer.house_id, { motto, houseName }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'House profile update failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  return null;
}
