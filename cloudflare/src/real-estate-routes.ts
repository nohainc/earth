import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { cancelConstructionProject, getConstructionQuote, getTerritoryCapacity, listConstructionProjects, purchaseBuildingInTerritory } from './territory-capacity-postgres.ts';
import {
  startCorporationBuildingResearch,
  listCorporationBuildingResearch,
} from './corporation-building-research-postgres.ts';
import { getBuildingCapitalOptions } from './building-age-postgres.ts';
import { acquireTerritoryRight, listTerritoryRights, releaseTerritoryRight } from './territory-rights-postgres.ts';
import { declareCommonsDividend, getCommonsStatement } from './commons-dividends-postgres.ts';

export async function handleRealEstateRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  const territoryRightsMatch = url.pathname.match(/^\/api\/territories\/([^/]+)\/rights$/);
  if (territoryRightsMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listTerritoryRights(repository, { territoryId: territoryRightsMatch[1] }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Territory rights unavailable' }, { status: 400 }); }
  }
  const commonsMatch = url.pathname.match(/^\/api\/territories\/([^/]+)\/commons$/);
  if (commonsMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getCommonsStatement(repository, commonsMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Commons statement unavailable' }, { status: 400 }); }
  }
  if (commonsMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ gameDay?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => declareCommonsDividend(repository, { humanId: viewer.id, territoryId: commonsMatch[1], gameDay: parsed.value.gameDay, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Commons dividend declaration failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/real-estate/rights' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listTerritoryRights(repository, { humanId: viewer.id }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Lease portfolio unavailable' }, { status: 400 }); }
  }
  if (url.pathname === '/api/real-estate/rights' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ territoryId?: string; slotClass?: 'PRIVATE' | 'PUBLIC'; slotQuantity?: string; termDays?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.territoryId || !parsed.value.slotQuantity || parsed.value.termDays === undefined) return Response.json({ ok: false, error: 'Territory, quantity, term, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => acquireTerritoryRight(repository, { humanId: viewer.id, territoryId: parsed.value.territoryId!, slotClass: parsed.value.slotClass ?? 'PRIVATE', slotQuantity: BigInt(parsed.value.slotQuantity!), termDays: parsed.value.termDays!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Territory right acquisition failed' }, { status: 409 }); }
  }
  const releaseRightMatch = url.pathname.match(/^\/api\/real-estate\/rights\/([^/]+)\/release$/);
  if (releaseRightMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => releaseTerritoryRight(repository, { humanId: viewer.id, rightId: releaseRightMatch[1], correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Territory right release failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/real-estate/projects' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listConstructionProjects(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Construction projects unavailable' }, { status: 400 });
    }
  }
  const capitalOptionsMatch = url.pathname.match(/^\/api\/real-estate\/buildings\/([^/]+)\/capital-options$/);
  if (capitalOptionsMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getBuildingCapitalOptions(repository, capitalOptionsMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Capital options unavailable' }, { status: 404 }); }
  }

  const cancelMatch = url.pathname.match(/^\/api\/real-estate\/projects\/([^/]+)\/cancel$/);
  if (cancelMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => cancelConstructionProject(repository, viewer.id, cancelMatch[1], correlationId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Construction cancellation failed' }, { status: 409 });
    }
  }
  const territoryCapacityMatch = url.pathname.match(/^\/api\/territories\/([^/]+)\/capacity$/);
  if (territoryCapacityMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getTerritoryCapacity(repository, territoryCapacityMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Territory capacity unavailable' }, { status: 404 });
    }
  }

  if (url.pathname === '/api/real-estate/quote' && request.method === 'GET') {
    const territoryId = url.searchParams.get('territoryId')?.trim();
    const buildingType = url.searchParams.get('buildingType')?.trim();
    const viewerId = viewer.id;
    if (!territoryId || !buildingType) return Response.json({ ok: false, error: 'Territory ID and building type are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => getConstructionQuote(repository, { ownerId: viewerId, territoryId, buildingType }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Construction quote unavailable' }, { status: 400 });
    }
  }

  if (url.pathname === '/api/real-estate/purchase' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      buildingType?: string;
      name?: string;
      territoryId?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const buildingType = body.buildingType?.trim();
    const name = body.name?.trim() || '';
    const territoryId = body.territoryId?.trim();
    if (!buildingType || !territoryId) {
      return Response.json({ ok: false, error: 'Building type and Territory ID are required' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        purchaseBuildingInTerritory(repository, {
          ownerId: viewer.id,
          territoryId,
          buildingType,
          name,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Building construction failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|exceeded|capacity|quota/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/research/buildings' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      buildingType?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingType = parsed.value.buildingType?.trim();
    if (!buildingType) {
      return Response.json({ ok: false, error: 'Building type is required' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        startCorporationBuildingResearch(repository, {
          humanId: viewer.id,
          buildingType,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Building research initiation failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|already|not found|only to corporation/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/research/buildings' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) =>
        listCorporationBuildingResearch(repository, viewer.id),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Building research list failed';
      return Response.json({ ok: false, error: message }, { status: 400 });
    }
  }

  return null;
}
