import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { cancelConstructionProject, getTerritoryCapacity, listConstructionProjects } from './territory-capacity-postgres.ts';
import {
  startCorporationBuildingResearch,
  quoteCorporationBuildingResearch,
  listCorporationBuildingResearch,
} from './corporation-building-research-postgres.ts';
import { getBuildingCapitalOptions, startBuildingCapitalProject } from './building-age-postgres.ts';
import { acquireTerritoryRight, listTerritoryRights, releaseTerritoryRight } from './territory-rights-postgres.ts';
import { declareCommonsDividend, getCommonsStatement } from './commons-dividends-postgres.ts';
import { decommissionBuilding, quoteBuildingDemolition, quoteBuildingOperatingMode, quoteBuildingUpgrade, setBuildingOperatingMode, upgradeBuilding } from './building-investment-postgres.ts';
import { purchaseV5Building, quoteV5Building } from './v5-building-postgres.ts';
import { isSettlementBarrierError } from './settlement-barrier-postgres.ts';

export async function handleRealEstateRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/v5/buildings' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingType?: string; name?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.buildingType || !parsed.value.name?.trim()) return Response.json({ ok: false, error: 'Building type, name, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => purchaseV5Building(repository, { ownerId: viewer.id, buildingType: parsed.value.buildingType!, name: parsed.value.name!.trim(), correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 pooled construction failed' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/v5/buildings/quote' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingType?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingType = parsed.value.buildingType?.trim();
    if (!buildingType) return Response.json({ ok: false, error: 'Building type is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => quoteV5Building(repository, { ownerId: viewer.id, buildingType }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 construction quote unavailable' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/real-estate/upgrade' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Territory-bound building upgrades are retired; use /api/v5/buildings/{id}/upgrade.' }, { status: 410 });
  }
  const v5UpgradeMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/upgrade$/);
  if (v5UpgradeMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => upgradeBuilding(repository, { buildingId: v5UpgradeMatch[1], humanId: viewer.id, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building upgrade failed' }, { status: 409 });
    }
  }
  const upgradeQuoteMatch = url.pathname.match(/^\/api\/real-estate\/buildings\/([^/]+)\/upgrade-quote$/);
  if (upgradeQuoteMatch && request.method === 'GET') {
    return Response.json({ ok: false, error: 'Territory-bound building upgrade quotes are retired; use /api/v5/buildings/{id}/upgrade-quote.' }, { status: 410 });
  }
  const v5UpgradeQuoteMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/upgrade-quote$/);
  if (v5UpgradeQuoteMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => quoteBuildingUpgrade(repository, { buildingId: v5UpgradeQuoteMatch[1], humanId: viewer.id }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building upgrade quote unavailable' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/real-estate/policy' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Legacy building policy mutations are retired; use /api/v5/buildings/{id}/policy.' }, { status: 410 });
  }
  const v5PolicyMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/policy$/);
  if (v5PolicyMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; policy?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.buildingId || !parsed.value.policy) return Response.json({ ok: false, error: 'Building ID, policy, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => setBuildingOperatingMode(repository, { buildingId: v5PolicyMatch[1], humanId: viewer.id, mode: parsed.value.policy!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building policy update failed' }, { status: 409 });
    }
  }
  const policyQuoteMatch = url.pathname.match(/^\/api\/real-estate\/buildings\/([^/]+)\/policy-quote$/);
  if (policyQuoteMatch && request.method === 'GET') {
    return Response.json({ ok: false, error: 'Legacy building policy quotes are retired; use /api/v5/buildings/{id}/policy-quote.' }, { status: 410 });
  }
  const v5PolicyQuoteMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/policy-quote$/);
  if (v5PolicyQuoteMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => quoteBuildingOperatingMode(repository, { buildingId: v5PolicyQuoteMatch[1], humanId: viewer.id }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building policy quote unavailable' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/real-estate/demolish' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Legacy building demolition is retired; use /api/v5/buildings/{id}/demolish.' }, { status: 410 });
  }
  const v5DemolishMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/demolish$/);
  if (v5DemolishMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.buildingId) return Response.json({ ok: false, error: 'Building ID and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => decommissionBuilding(repository, { buildingId: v5DemolishMatch[1], humanId: viewer.id, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building decommission failed' }, { status: 409 });
    }
  }
  const demolitionQuoteMatch = url.pathname.match(/^\/api\/real-estate\/buildings\/([^/]+)\/demolition-quote$/);
  if (demolitionQuoteMatch && request.method === 'GET') {
    return Response.json({ ok: false, error: 'Legacy building demolition quotes are retired; use /api/v5/buildings/{id}/demolition-quote.' }, { status: 410 });
  }
  const v5DemolitionQuoteMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/demolition-quote$/);
  if (v5DemolitionQuoteMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => quoteBuildingDemolition(repository, { buildingId: v5DemolitionQuoteMatch[1], humanId: viewer.id }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building demolition quote unavailable' }, { status: 409 }); }
  }
  const territoryRightsMatch = url.pathname.match(/^\/api\/territories\/([^/]+)\/rights$/);
  if (territoryRightsMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listTerritoryRights(repository, { territoryId: territoryRightsMatch[1], humanId: viewer.id }));
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
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => declareCommonsDividend(repository, { humanId: viewer.id, territoryId: commonsMatch[1], correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Commons dividend declaration failed' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/real-estate/rights' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listTerritoryRights(repository, { humanId: viewer.id }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Lease portfolio unavailable' }, { status: 400 });
    }
  }
  if (url.pathname === '/api/real-estate/rights' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Territory use-right acquisition is retired in V5; use pooled capacity construction.' }, { status: 410 });
  }
  const releaseRightMatch = url.pathname.match(/^\/api\/real-estate\/rights\/([^/]+)\/release$/);
  if (releaseRightMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Territory use-right release is retired in V5; capacity is derived from active assets.' }, { status: 410 });
  }
  if (url.pathname === '/api/real-estate/projects' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listConstructionProjects(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Construction projects unavailable' }, { status: 400 });
    }
  }
  const capitalOptionsMatch = url.pathname.match(/^\/api\/real-estate\/buildings\/([^/]+)\/capital-options$/);
  if (capitalOptionsMatch && request.method === 'GET') {
    return Response.json({ ok: false, error: 'Legacy capital options are retired; use /api/v5/buildings/{id}/capital-options.' }, { status: 410 });
  }
  const v5CapitalOptionsMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/capital-options$/);
  if (v5CapitalOptionsMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getBuildingCapitalOptions(repository, v5CapitalOptionsMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Capital options unavailable' }, { status: 404 });
    }
  }

  const capitalProjectMatch = url.pathname.match(/^\/api\/real-estate\/buildings\/([^/]+)\/capital-projects$/);
  if (capitalProjectMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Legacy capital projects are retired; use /api/v5/buildings/{id}/capital-projects.' }, { status: 410 });
  }
  const v5CapitalProjectMatch = url.pathname.match(/^\/api\/v5\/buildings\/([^/]+)\/capital-projects$/);
  if (v5CapitalProjectMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ projectKind?: 'OVERHAUL' | 'GENERATION_RETROFIT'; targetGenerationId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.projectKind) return Response.json({ ok: false, error: 'Project kind and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => startBuildingCapitalProject(repository, { buildingId: v5CapitalProjectMatch[1], humanId: viewer.id, projectKind: parsed.value.projectKind!, targetGenerationId: parsed.value.targetGenerationId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Capital project failed' }, { status: 409 });
    }
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
      if (isSettlementBarrierError(error)) return error.toResponse();
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
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Territory capacity unavailable' }, { status: 404 });
    }
  }

  if (url.pathname === '/api/real-estate/quote' && request.method === 'GET') {
    return Response.json({ ok: false, error: 'Territory-bound construction is retired; use the V5 pooled construction quote.' }, { status: 410 });
  }

  if (url.pathname === '/api/real-estate/purchase' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Territory-bound construction is retired; use /api/v5/buildings.' }, { status: 410 });
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
      if (isSettlementBarrierError(error)) return error.toResponse();
      const message = error instanceof Error ? error.message : 'Building research initiation failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|already|not found|only to corporation/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/research/buildings/quote' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingType?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingType = parsed.value.buildingType?.trim();
    if (!buildingType) return Response.json({ ok: false, error: 'Building type is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => quoteCorporationBuildingResearch(repository, { humanId: viewer.id, buildingType }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building research quote unavailable' }, { status: 409 });
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
