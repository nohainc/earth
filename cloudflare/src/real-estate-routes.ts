import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { getConstructionQuote, getTerritoryCapacity, purchaseBuildingInTerritory } from './territory-capacity-postgres.ts';
import {
  startCorporationBuildingResearch,
  listCorporationBuildingResearch,
} from './corporation-building-research-postgres.ts';

export async function handleRealEstateRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
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
