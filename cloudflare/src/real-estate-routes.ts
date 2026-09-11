import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  purchasePrivatePlotAndConstruct,
  upgradeBuilding,
  completeBuildingConstruction,
  setBuildingOperatingPolicy,
  demolishBuilding,
  contributeCorporateResearch,
} from './real-estate-postgres.ts';
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
  if (url.pathname === '/api/real-estate/purchase' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      buildingType?: string;
      name?: string;
      cityId?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const buildingType = body.buildingType?.trim();
    const name = body.name?.trim() || '';
    const cityId = body.cityId?.trim() || 'CITY-0084';
    if (!buildingType) {
      return Response.json({ ok: false, error: 'Building type is required' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        purchasePrivatePlotAndConstruct(repository, {
          ownerId: viewer.id,
          cityId,
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

  if (url.pathname === '/api/real-estate/upgrade' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const buildingId = body.buildingId?.trim();
    if (!buildingId) return Response.json({ ok: false, error: 'Building ID is required' }, { status: 400 });
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        upgradeBuilding(repository, {
          humanId: viewer.id,
          buildingId,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Building upgrade failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|not found|unauthorized|research/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/real-estate/complete-construction' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingId = parsed.value.buildingId?.trim();
    if (!buildingId) return Response.json({ ok: false, error: 'Building ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        completeBuildingConstruction(repository, {
          humanId: viewer.id,
          buildingId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Complete construction failed';
      return Response.json({ ok: false, error: message }, { status: /not finished|not found|unauthorized|only the property/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/real-estate/policy' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; policy?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingId = parsed.value.buildingId?.trim();
    const policy = parsed.value.policy?.trim() as any;
    if (!buildingId || !policy) return Response.json({ ok: false, error: 'Building ID and policy are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setBuildingOperatingPolicy(repository, {
          humanId: viewer.id,
          buildingId,
          policy,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Policy update failed';
      return Response.json({ ok: false, error: message }, { status: /unauthorized|not found/i.test(message) ? 403 : 400 });
    }
  }

  if (url.pathname === '/api/real-estate/demolish' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingId = parsed.value.buildingId?.trim();
    if (!buildingId) return Response.json({ ok: false, error: 'Building ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        demolishBuilding(repository, {
          humanId: viewer.id,
          buildingId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Demolition failed';
      return Response.json({ ok: false, error: message }, { status: /cannot be demolished|unauthorized|only the owner/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/corporate-research/contribute' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      poolId?: string;
      credits?: number;
      compute?: number;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const poolId = body.poolId?.trim();
    const credits = Number(body.credits ?? 0);
    const compute = Number(body.compute ?? 0);
    if (!poolId || (credits <= 0 && compute <= 0)) {
      return Response.json({ ok: false, error: 'Pool ID and positive contribution are required' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        contributeCorporateResearch(repository, {
          humanId: viewer.id,
          poolId,
          credits,
          compute,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Contribution failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|not found|not a member/i.test(message) ? 409 : 400 });
    }
  }

  if ((url.pathname === '/api/corporation/building-research' || url.pathname === '/api/corporations/building-research') && request.method === 'POST') {
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

  if ((url.pathname === '/api/corporation/building-research' || url.pathname === '/api/corporations/building-research') && request.method === 'GET') {
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
