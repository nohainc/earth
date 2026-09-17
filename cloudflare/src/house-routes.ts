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
import { getHouseDailySummary } from './house-daily-summary-postgres.ts';
import { getHouseAutomation, listHousePolicies, saveHouseAutomation, saveHousePolicy } from './house-policy-postgres.ts';
import { advanceHouseOnboarding, getHouseOnboarding } from './house-onboarding-postgres.ts';
import { getHouseResidency, moveHouseResidence, quoteHouseMove } from './residency-postgres.ts';
import { claimHouseEntrySupport, getHouseEntrySupport } from './catch-up-postgres.ts';
import { getHouseCatchUpTargets } from './catch-up-targets-postgres.ts';

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
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => listHousePolicies(repository, viewer.house_id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/house/policies' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<Record<string, unknown>>(request);
    if (!parsed.ok) return parsed.response;
    const value = parsed.value;
    try {
      const result = await withRepository(env, (repository) => saveHousePolicy(repository, viewer.house_id, {
        policyType: String(value.policyType ?? '').toUpperCase() as 'OPERATING' | 'INVENTORY_RESERVE' | 'MARKET_STANDING',
        operatingMode: String(value.operatingMode ?? 'BALANCED').toUpperCase() as 'CONSERVATIVE' | 'BALANCED' | 'GROWTH' | 'CUSTOM',
        effectiveFromGameDay: Number(value.effectiveFromGameDay), dailySpendCapUnits: String(value.dailySpendCapUnits ?? '0'),
        reserveFloorUnits: (value.reserveFloorUnits ?? {}) as Record<string, string | number>, maxInputPriceUnits: (value.maxInputPriceUnits ?? {}) as Record<string, string | number>, minSalePriceUnits: (value.minSalePriceUnits ?? {}) as Record<string, string | number>, procurementQuantityUnits: (value.procurementQuantityUnits ?? {}) as Record<string, string | number>, correlationId: resolveIdempotencyKey(request, String(value.correlationId ?? '')),
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Policy save failed' }, { status: 400 });
    }
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
        operatingMode: String(value.operatingMode ?? 'BALANCED').toUpperCase() as 'CONSERVATIVE' | 'BALANCED' | 'GROWTH' | 'CUSTOM',
        effectiveFromGameDay: Number(value.effectiveFromGameDay), dailySpendCapUnits: String(value.dailySpendCapUnits ?? '0'),
        reserveFloorUnits: (value.reserveFloorUnits ?? {}) as Record<string, string | number>, maxInputPriceUnits: (value.maxInputPriceUnits ?? {}) as Record<string, string | number>, minSalePriceUnits: (value.minSalePriceUnits ?? {}) as Record<string, string | number>, procurementQuantityUnits: (value.procurementQuantityUnits ?? {}) as Record<string, string | number>, correlationId: resolveIdempotencyKey(request, String(value.correlationId ?? '')),
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Automation save failed' }, { status: 400 });
    }
  }

  // GET /api/house — overview of lineage, perks, and heirlooms
  if (url.pathname === '/api/house' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getHouseOverview(repository, viewer.house_id, viewer.id, viewer.display_name));
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
        unlockHousePerk(repository, viewer.house_id, perkKey, 1, resolveIdempotencyKey(request, parsed.value.correlationId)),
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
          viewer.house_id,
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
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const name = parsed.value.name?.trim() ?? '';
    const heirloomType = parsed.value.heirloomType?.trim() ?? 'house_standard';
    const inscription = parsed.value.inscription?.trim() ?? 'Forged by the house patriarch.';
    if (!name) return Response.json({ ok: false, error: 'Heirloom name is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        forgeHouseHeirloom(
          repository,
          viewer.house_id,
          name,
          heirloomType,
          inscription,
          '',
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
          viewer.house_id,
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
