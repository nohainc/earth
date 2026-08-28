import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  purchasePrivatePlotAndConstruct,
  upgradeBuilding,
  setBuildingOperatingPolicy,
  repairBuilding,
  investInPublicBuilding,
  demolishBuilding,
  getCityDistrictZoning,
  getCivicDividendHistory,
  contributeCorporateResearch,
  acquireBuildingPatentLicense,
  renewBuildingPatentLicense,
} from './real-estate-postgres.ts';

export async function handleRealEstateRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/real-estate/license/acquire' || url.pathname === '/api/real-estate/license/renew') {
    return Response.json({ ok: false, error: 'Patent licensing has been retired' }, { status: 404 });
  }
  if (url.pathname === '/api/real-estate/purchase' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      cityId?: string;
      buildingType?: string;
      name?: string;
      businessId?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const cityId = body.cityId?.trim() ?? 'CITY-0084';
    const buildingType = body.buildingType?.trim() ?? '';
    const name = body.name?.trim() ?? '';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!buildingType || !correlationId) {
      return Response.json({ ok: false, error: 'Building type and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        purchasePrivatePlotAndConstruct(repository, {
          ownerId: viewer.id,
          cityId,
          buildingType,
          name,
          businessId: body.businessId,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Real estate acquisition failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/upgrade' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const buildingId = body.buildingId?.trim() ?? '';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!buildingId || !correlationId) {
      return Response.json({ ok: false, error: 'Building ID and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        upgradeBuilding(repository, { humanId: viewer.id, buildingId, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building upgrade failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/repair' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingId = parsed.value.buildingId?.trim() ?? '';
    if (!buildingId) return Response.json({ ok: false, error: 'Building ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        repairBuilding(repository, { humanId: viewer.id, buildingId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Repair failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/policy' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; policy?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingId = parsed.value.buildingId?.trim() ?? '';
    const policy = (parsed.value.policy?.trim() ?? 'balanced') as any;
    if (!buildingId) return Response.json({ ok: false, error: 'Building ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setBuildingOperatingPolicy(repository, { humanId: viewer.id, buildingId, policy }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Policy update failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/invest' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; sharesCount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const buildingId = body.buildingId?.trim() ?? '';
    const sharesCount = Math.max(1, Math.floor(body.sharesCount ?? 1));
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!buildingId || !correlationId) {
      return Response.json({ ok: false, error: 'Building ID and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        investInPublicBuilding(repository, { humanId: viewer.id, buildingId, sharesCount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share investment failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/demolish' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingId = parsed.value.buildingId?.trim() ?? '';
    if (!buildingId) return Response.json({ ok: false, error: 'Building ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        demolishBuilding(repository, { humanId: viewer.id, buildingId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Demolition failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/zoning' && request.method === 'GET') {
    const cityId = url.searchParams.get('cityId')?.trim() ?? 'CITY-0084';
    try {
      const result = await withRepository(env, (repository) => getCityDistrictZoning(repository, cityId));
      return Response.json({ ok: true, zoning: result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Zoning query failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/dividends' && request.method === 'GET') {
    const cityId = url.searchParams.get('cityId')?.trim() ?? 'CITY-0084';
    try {
      const result = await withRepository(env, (repository) => getCivicDividendHistory(repository, cityId, viewer.id));
      return Response.json({ ok: true, dividends: result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Dividend query failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/corporate-research/contribute' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ poolId?: string; credits?: number; compute?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const poolId = body.poolId?.trim() ?? '';
    const credits = Number(body.credits ?? 0);
    const compute = Number(body.compute ?? 0);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!poolId || !correlationId) {
      return Response.json({ ok: false, error: 'Pool ID and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        contributeCorporateResearch(repository, { humanId: viewer.id, poolId, credits, compute, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'R&D contribution failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/license/acquire' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      patentId?: string;
      licenseType?: 'private_building' | 'city_civic';
      buildingId?: string;
      cityId?: string;
      isPermanent?: boolean;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const patentId = body.patentId?.trim() ?? '';
    const licenseType = body.licenseType ?? 'private_building';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!patentId || !correlationId) {
      return Response.json({ ok: false, error: 'Patent ID and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        acquireBuildingPatentLicense(repository, {
          humanId: viewer.id,
          patentId,
          licenseType,
          buildingId: body.buildingId,
          cityId: body.cityId,
          isPermanent: body.isPermanent,
          correlationId,
        }),
      );
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'License acquisition failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/real-estate/license/renew' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ licenseId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const licenseId = body.licenseId?.trim() ?? '';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!licenseId || !correlationId) {
      return Response.json({ ok: false, error: 'License ID and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        renewBuildingPatentLicense(repository, {
          humanId: viewer.id,
          licenseId,
          correlationId,
        }),
      );
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'License renewal failed' }, { status: 409 });
    }
  }

  return null;
}
