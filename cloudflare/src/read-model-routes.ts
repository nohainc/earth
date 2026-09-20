import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { currentHuman, currentViewer } from './auth-session.ts';
import {
  auditWorld as auditWorldPostgres,
  listCemeteryProfiles as listCemeteryProfilesPostgres,
  listInstitutions as listInstitutionsPostgres,
  listMarketPriceHistory as listMarketPriceHistoryPostgres,
  listPantheonOfAchievements as listPantheonOfAchievementsPostgres,
  listRankings as listRankingsPostgres,
} from './read-postgres.ts';
import { listEvents as listEventsPostgres, listHistory as listHistoryPostgres } from './read-models/events-read.ts';
import { listNews as listNewsPostgres, markNewsSeen as markNewsSeenPostgres } from './read-models/news-read.ts';
import { backfillV5CapacityBatch, getV5CapacityBackfillRun } from './v5-capacity-backfill-postgres.ts';
import { getV5CutoverReadiness } from './v5-cutover-readiness-postgres.ts';
import { getV5TaxReconciliation } from './v5-tax-reconciliation-postgres.ts';
import { listNotifications as listNotificationsPostgres, markAllNotificationsRead as markAllNotificationsReadPostgres, markNotificationRead as markNotificationReadPostgres } from './read-models/notifications-read.ts';
import { getDecisionQueue } from './decision-queue-postgres.ts';
import { contributeToGlobalProgram, listGlobalProgramContributions, listGlobalPrograms } from './global-programs-postgres.ts';
import { getTechnologyGenerations } from './technology-generations-postgres.ts';
import { getEarthTechnologyFrontier } from './earth-technology-frontier-postgres.ts';
import { contributeToPublicProject, getPublicProject, listPublicProjects } from './public-projects-postgres.ts';
import { listWorldConditions } from './world-conditions-postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { featureDisabledResponse, featureEnabled } from './feature-config.ts';
import { addMutualCreditGuarantee, createMutualCreditNetwork, getMutualCreditNetwork, joinMutualCreditNetwork, listMutualCreditNetworks, transferMutualCredit } from './mutual-credit-postgres.ts';
import { getActiveV5StandardCapacity, getV5CorporationCapacity, getV5EarthCapacity, getV5HouseCapacity } from './v5-capacity-postgres.ts';
import { getV5Overview } from './v5-overview-postgres.ts';
import { parseCreditAmount } from './money.ts';
import { contributeToInitiative, listInitiatives, quoteInitiativeContribution } from './initiatives-postgres.ts';

function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)])) as T;
  return value;
}

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

  const v5HouseCapacity = url.pathname === '/api/v5/house/capacity' && request.method === 'GET';
  if (v5HouseCapacity) {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => getV5HouseCapacity(repository, viewer.house_id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, capacity: toJsonSafe(result), persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/v5/command/overview' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getV5Overview(repository, viewer.house_id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      // The overview aggregates canonical capacity facts, which may contain
      // bigint values even though individual sub-read models are wire-safe.
      // Normalize the complete envelope before Response.json serializes it.
      return Response.json({ ...toJsonSafe(result), persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 overview unavailable' }, { status: 400 });
    }
  }
  if (url.pathname === '/api/v5/capacity' && request.method === 'GET') {
    if (!await currentHuman(request, env)) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => getV5EarthCapacity(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, capacity: toJsonSafe(result), persistence: 'planetscale-postgres' });
  }
  const v5CorporationCapacity = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/capacity$/);
  if (v5CorporationCapacity && request.method === 'GET') {
    if (!await currentHuman(request, env)) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, async (repository) => {
      const policy = await getActiveV5StandardCapacity(repository);
      return { ...(await getV5CorporationCapacity(repository, v5CorporationCapacity[1], policy.standardTerritoryCapacity)), policyVersion: policy.policyVersion, gameDay: policy.gameDay };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, capacity: toJsonSafe(result), persistence: 'planetscale-postgres' });
  }

  const mutualCreditDetail = url.pathname.match(/^\/api\/mutual-credit\/networks\/([^/]+)$/);
  if (url.pathname === '/api/mutual-credit/networks' && request.method === 'GET') {
    if (!featureEnabled(env, 'mutualCredit')) return featureDisabledResponse('mutualCredit');
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => listMutualCreditNetworks(repository, viewer.house_id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (mutualCreditDetail && request.method === 'GET') {
    if (!featureEnabled(env, 'mutualCredit')) return featureDisabledResponse('mutualCredit');
    if (!await currentHuman(request, env)) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => getMutualCreditNetwork(repository, mutualCreditDetail[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Mutual-credit network fetch failed' }, { status: 404 }); }
  }
  const mutualCreditJoin = url.pathname.match(/^\/api\/mutual-credit\/networks\/([^/]+)\/join$/);
  const mutualCreditTransfer = url.pathname.match(/^\/api\/mutual-credit\/networks\/([^/]+)\/transfers$/);
  const mutualCreditGuarantee = url.pathname.match(/^\/api\/mutual-credit\/networks\/([^/]+)\/guarantees$/);
  if (mutualCreditJoin && request.method === 'POST') {
    if (!featureEnabled(env, 'mutualCredit')) return featureDisabledResponse('mutualCredit');
    const viewer = await currentHuman(request, env); if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ creditLimitUnits?: string; correlationId?: string }>(request); if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId); if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => joinMutualCreditNetwork(repository, { humanId: viewer.id, networkId: mutualCreditJoin[1], creditLimitUnits: parsed.value.creditLimitUnits ? BigInt(parsed.value.creditLimitUnits) : undefined, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Mutual-credit join failed' }, { status: 409 }); }
  }
  if (mutualCreditTransfer && request.method === 'POST') {
    if (!featureEnabled(env, 'mutualCredit')) return featureDisabledResponse('mutualCredit');
    const viewer = await currentHuman(request, env); if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ toHouseId?: string; amountUnits?: string; correlationId?: string }>(request); if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId); if (!correlationId || !parsed.value.toHouseId || !parsed.value.amountUnits) return Response.json({ ok: false, error: 'Recipient, amount, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => transferMutualCredit(repository, { humanId: viewer.id, networkId: mutualCreditTransfer[1], toHouseId: parsed.value.toHouseId!, amountUnits: BigInt(parsed.value.amountUnits!), correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Mutual-credit transfer failed' }, { status: 409 }); }
  }
  if (mutualCreditGuarantee && request.method === 'POST') {
    if (!featureEnabled(env, 'mutualCredit')) return featureDisabledResponse('mutualCredit');
    const viewer = await currentHuman(request, env); if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ memberHouseId?: string; guaranteedUnits?: string; correlationId?: string }>(request); if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId); if (!correlationId || !parsed.value.memberHouseId || !parsed.value.guaranteedUnits) return Response.json({ ok: false, error: 'Member, guarantee amount, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => addMutualCreditGuarantee(repository, { humanId: viewer.id, networkId: mutualCreditGuarantee[1], memberHouseId: parsed.value.memberHouseId!, guaranteedUnits: BigInt(parsed.value.guaranteedUnits!), correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Mutual-credit guarantee failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/mutual-credit/networks' && request.method === 'POST') {
    if (!featureEnabled(env, 'mutualCredit')) return featureDisabledResponse('mutualCredit');
    const viewer = await currentHuman(request, env); if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ organizationId?: string; name?: string; unitCode?: string; maxMemberLimitUnits?: string; reserveTargetUnits?: string; correlationId?: string }>(request); if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId); if (!correlationId || !parsed.value.organizationId || !parsed.value.name || !parsed.value.unitCode || !parsed.value.maxMemberLimitUnits) return Response.json({ ok: false, error: 'Organization, network definition, limit, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createMutualCreditNetwork(repository, { humanId: viewer.id, organizationId: parsed.value.organizationId!, name: parsed.value.name!, unitCode: parsed.value.unitCode!, maxMemberLimitUnits: BigInt(parsed.value.maxMemberLimitUnits!), reserveTargetUnits: parsed.value.reserveTargetUnits ? BigInt(parsed.value.reserveTargetUnits) : undefined, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Mutual-credit network creation failed' }, { status: 409 }); }
  }

  if ((url.pathname === '/api/command-center' || url.pathname === '/api/decisions') && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const rawLimit = Number(url.searchParams.get('limit') ?? 20);
    if (!Number.isInteger(rawLimit) || rawLimit < 1 || rawLimit > 100) return Response.json({ ok: false, error: 'limit must be an integer between 1 and 100' }, { status: 400 });
    const result = await withRepository(env, (repository) => getDecisionQueue(repository, viewer.house_id, rawLimit));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/buildings/catalog' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => repository.query(
      `SELECT c.id, c.code, c.name, c.description, c.category,
              c.family_code, c.tier, c.tier_formula_version,
              c.economic_role,
              c.construction_credit_units, c.construction_minutes,
              c.research_credit_units, c.research_duration_game_days,
              c.operating_credit_units, c.service_type, c.service_capacity_units,
              c.slot_footprint, c.definition_version,
              COALESCE(jsonb_agg(jsonb_build_object(
                'assetCode', a.code,
                'constructionUnits', f.construction_units::TEXT,
                'operatingInputUnits', f.operating_input_units::TEXT,
                'operatingOutputUnits', f.operating_output_units::TEXT
              ) ORDER BY a.code) FILTER (WHERE f.asset_id IS NOT NULL), '[]'::jsonb) AS resource_flows
         FROM building_catalog c
         LEFT JOIN building_catalog_resource_flows f ON f.catalog_id = c.id
         LEFT JOIN economic_assets a ON a.id = f.asset_id
        GROUP BY c.id, c.code, c.family_code, c.tier, c.tier_formula_version,
                 c.name, c.description, c.category, c.economic_role,
                 c.construction_credit_units, c.construction_minutes,
                 c.research_credit_units, c.research_duration_game_days,
                 c.operating_credit_units, c.service_type, c.service_capacity_units,
                 c.slot_footprint, c.definition_version
        ORDER BY code, tier, id`,
    ));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ catalog: result.rows, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/earth/programs' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listGlobalPrograms(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/initiatives' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const status = url.searchParams.get('status')?.toUpperCase();
    const scope = url.searchParams.get('scope')?.toUpperCase() as 'EARTH' | 'CORPORATION' | undefined;
    const mySupport = url.searchParams.get('mySupport') === 'true';
    const result = await withRepository(env, (repository) => listInitiatives(repository, viewer.house_id, { status, scope, mySupport }));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  const initiativeContributionMatch = url.pathname.match(/^\/api\/initiatives\/([^/]+)\/contributions$/);
  const initiativeContributionQuoteMatch = url.pathname.match(/^\/api\/initiatives\/([^/]+)\/contribution-quote$/);
  if (initiativeContributionQuoteMatch && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ amountCredit?: string }>(request);
    if (!parsed.ok) return parsed.response;
    if (!parsed.value.amountCredit) return Response.json({ ok: false, error: 'Decimal CREDIT amount is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => quoteInitiativeContribution(repository, { initiativeId: initiativeContributionQuoteMatch[1], houseId: viewer.houseId, amountUnits: parseCreditAmount(parsed.value.amountCredit!).toString() }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, quote: result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Initiative contribution quote failed' }, { status: 409 }); }
  }
  if (initiativeContributionMatch && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ amountCredit?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.amountCredit) return Response.json({ ok: false, error: 'Decimal CREDIT amount and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => contributeToInitiative(repository, { initiativeId: initiativeContributionMatch[1], houseId: viewer.houseId, amountUnits: parseCreditAmount(parsed.value.amountCredit).toString(), correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Initiative contribution failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/earth/technology/generations' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getTechnologyGenerations(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/earth/technology/frontier' && request.method === 'GET') {
    const rawDay = url.searchParams.get('day');
    const day = rawDay == null ? undefined : Number(rawDay);
    if (day != null && (!Number.isInteger(day) || day < 1)) return Response.json({ ok: false, error: 'day must be a positive integer' }, { status: 400 });
    const result = await withRepository(env, (repository) => getEarthTechnologyFrontier(repository, day));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/world/conditions' && request.method === 'GET') {
    const rawDay = url.searchParams.get('day');
    const day = rawDay == null ? undefined : Number(rawDay);
    if (day != null && (!Number.isInteger(day) || day < 1)) return Response.json({ ok: false, error: 'day must be a positive integer' }, { status: 400 });
    const result = await withRepository(env, (repository) => listWorldConditions(repository, day));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/public-projects' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listPublicProjects(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/public-projects' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Direct public-project creation is retired; propose an Initiative through V5 Governance.' }, { status: 410 });
  }
  const publicProjectDetailMatch = url.pathname.match(/^\/api\/public-projects\/([^/]+)$/);
  if (publicProjectDetailMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getPublicProject(repository, publicProjectDetailMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  const publicProjectContributionMatch = url.pathname.match(/^\/api\/public-projects\/([^/]+)\/contributions$/);
  if (publicProjectContributionMatch && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ amountCredit?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.amountCredit) return Response.json({ ok: false, error: 'Decimal CREDIT amount and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => contributeToPublicProject(repository, { projectId: publicProjectContributionMatch[1], houseId: viewer.houseId, amountUnits: parseCreditAmount(parsed.value.amountCredit).toString(), humanId: viewer.id, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Public contribution failed' }, { status: 409 }); }
  }
  const publicProjectFundMatch = url.pathname.match(/^\/api\/public-projects\/([^/]+)\/matching-fund$/);
  if (publicProjectFundMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Manual matching-pool funding is retired; matching is authorized and settled by the Initiative lifecycle.' }, { status: 410 });
  }
  const publicProjectSettleMatch = url.pathname.match(/^\/api\/public-projects\/([^/]+)\/settle$/);
  if (publicProjectSettleMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Manual public-project settlement is retired; the scheduler settles due Initiatives.' }, { status: 410 });
  }
  if (url.pathname === '/api/earth/programs' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Direct Earth-program creation is retired; propose an Initiative through V5 Governance.' }, { status: 410 });
  }
  const programFundingMatch = url.pathname.match(/^\/api\/earth\/programs\/([^/]+)\/fund$/);
  if (programFundingMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Manual Earth treasury funding is retired; Initiative treasury authorization is applied by Governance and settlement.' }, { status: 410 });
  }
  const programContributionMatch = url.pathname.match(/^\/api\/earth\/programs\/([^/]+)\/contributions$/);
  if (programContributionMatch && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ amountCredit?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.amountCredit) return Response.json({ ok: false, error: 'Decimal CREDIT amount and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => contributeToGlobalProgram(repository, { programId: programContributionMatch[1], houseId: viewer.houseId, amountUnits: parseCreditAmount(parsed.value.amountCredit).toString(), humanId: viewer.id, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Global program contribution failed' }, { status: 409 }); }
  }
  const programContributionListMatch = url.pathname.match(/^\/api\/earth\/programs\/([^/]+)\/contributions$/);
  if (programContributionListMatch && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => listGlobalProgramContributions(repository, programContributionListMatch[1], viewer.houseId));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json(result);
  }
  const programSettleMatch = url.pathname.match(/^\/api\/earth\/programs\/([^/]+)\/settle$/);
  if (programSettleMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Manual Earth-program settlement is retired; the scheduler settles due Initiatives.' }, { status: 410 });
  }

  // ── World activity ───────────────────────────────────────────────────────────
  if (url.pathname === '/api/world/activity' && request.method === 'GET') {
    const viewer = await currentViewer(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, async (repository) => {
      const [clock, worldBatch, technology] = await Promise.all([
        readAuthoritativeGameTime(repository),
        repository.query('SELECT market_batch_seconds FROM world_state WHERE id = $1', ['WORLD']),
        repository.query(`SELECT ROUND(p.progress_research_points * 100.0 / NULLIF(p.required_research_points, 0), 2) AS progress
          FROM corporation_research_projects p
          JOIN house_affiliations m ON m.corporation_id = (SELECT source_id FROM owner_registry WHERE economic_id = p.corporation_economic_id)
             AND m.status = 'ACTIVE'
          WHERE m.human_id = $1 AND p.target_type = 'TECHNOLOGY'
          ORDER BY p.created_at DESC LIMIT 1`, [viewer.id]),
      ]);
      return {
        activity: [
          { type: 'world_clock', day: clock.gameDay },
          { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 },
          { type: 'market_cycle', batch: worldBatch.rows[0]?.market_batch_seconds ?? 0 },
        ],
      };
    });
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  // ── Events / activity feed ───────────────────────────────────────────────────
  if (url.pathname === '/api/news' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const rawLimit = Number(url.searchParams.get('limit') ?? 25);
    if (!Number.isInteger(rawLimit) || rawLimit < 1 || rawLimit > 50) return Response.json({ ok: false, error: 'limit must be an integer between 1 and 50' }, { status: 400 });
    const scope = url.searchParams.get('scope')?.trim().toUpperCase() || undefined;
    const topic = url.searchParams.get('topic')?.trim().toUpperCase() || undefined;
    const importance = url.searchParams.get('importance')?.trim().toUpperCase() || undefined;
    if (scope && !['EARTH', 'CORPORATION', 'COMMUNITY'].includes(scope)) return Response.json({ ok: false, error: 'Unknown news scope' }, { status: 400 });
    if (topic && !['GOVERNANCE', 'TECHNOLOGY', 'ECONOMY', 'INFRASTRUCTURE', 'SOCIETY', 'LIFECYCLE'].includes(topic)) return Response.json({ ok: false, error: 'Unknown news topic' }, { status: 400 });
    if (importance && !['MAJOR', 'NOTABLE', 'ROUTINE'].includes(importance)) return Response.json({ ok: false, error: 'Unknown news importance' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => listNewsPostgres(repository, viewer.house_id, rawLimit, url.searchParams.get('before') ?? undefined, {
        scope: scope as 'EARTH' | 'CORPORATION' | 'COMMUNITY' | undefined,
        topic: topic as 'GOVERNANCE' | 'TECHNOLOGY' | 'ECONOMY' | 'INFRASTRUCTURE' | 'SOCIETY' | 'LIFECYCLE' | undefined,
        importance: importance as 'MAJOR' | 'NOTABLE' | 'ROUTINE' | undefined,
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'News feed unavailable' }, { status: 400 });
    }
  }

  if (url.pathname === '/api/news/seen' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ publicationKey?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const publicationKey = parsed.value.publicationKey?.trim();
    if (!publicationKey) return Response.json({ ok: false, error: 'publicationKey is required' }, { status: 400 });
    try {
      await withRepository(env, (repository) => markNewsSeenPostgres(repository, viewer.house_id, publicationKey));
      return Response.json({ ok: true });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'News read state unavailable' }, { status: 400 });
    }
  }

  if (url.pathname === '/api/events' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const requestedCategory = url.searchParams.get('category')?.trim().toUpperCase() || undefined;
    const allowedCategories = new Set(['ECONOMY', 'MARKET', 'BUILDING', 'AFFILIATION', 'OWNERSHIP', 'GOVERNANCE', 'RESEARCH', 'TECHNOLOGY', 'LIFECYCLE', 'BANKING', 'TAX', 'INSTITUTION', 'SYSTEM']);
    if (requestedCategory && !allowedCategories.has(requestedCategory)) return Response.json({ ok: false, error: 'Unknown event category' }, { status: 400 });
    const result = await withRepository(env, (repository) => listEventsPostgres(repository, limit, requestedCategory));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  // ── Notifications ────────────────────────────────────────────────────────────
  if (url.pathname === '/api/notifications' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
    const result = await withRepository(env, (repository) => listNotificationsPostgres(repository, viewer.houseId, limit));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/notifications/read-all' && request.method === 'POST') {
    const viewer = await currentViewer(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => markAllNotificationsReadPostgres(repository, viewer.houseId));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  const notificationReadMatch = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
  if (notificationReadMatch && request.method === 'POST') {
    const viewer = await currentViewer(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) =>
      markNotificationReadPostgres(repository, viewer.houseId, notificationReadMatch[1]),
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

  if (url.pathname === '/internal/audit' && request.method === 'GET') {
    const expectedToken = env.INTERNAL_ADMIN_TOKEN;
    const providedToken = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
    if (!expectedToken || providedToken !== expectedToken) return new Response(null, { status: 404 });
    const result = await withRepository(env, (repository) => auditWorldPostgres(repository, 'internal-admin'));
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/internal/v5/cutover-readiness' && request.method === 'GET') {
    const expectedToken = env.INTERNAL_ADMIN_TOKEN;
    const providedToken = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
    if (!expectedToken || providedToken !== expectedToken) return new Response(null, { status: 404 });
    const result = await withRepository(env, (repository) => getV5CutoverReadiness(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.eligible ? 200 : 503 });
  }

  if (url.pathname === '/internal/v5/tax-reconciliation' && request.method === 'GET') {
    const expectedToken = env.INTERNAL_ADMIN_TOKEN;
    const providedToken = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
    if (!expectedToken || providedToken !== expectedToken) return new Response(null, { status: 404 });
    const rawDay = url.searchParams.get('assessedGameDay');
    const assessedDay = rawDay === null ? undefined : Number(rawDay);
    if (assessedDay !== undefined && (!Number.isInteger(assessedDay) || assessedDay < 1)) return Response.json({ ok: false, error: 'assessedGameDay must be a positive integer' }, { status: 400 });
    const result = await withRepository(env, (repository) => getV5TaxReconciliation(repository, assessedDay));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if ((url.pathname === '/internal/v5/capacity-backfill' || url.pathname === '/internal/v5/capacity-backfill/run') && (request.method === 'GET' || request.method === 'POST')) {
    const expectedToken = env.INTERNAL_ADMIN_TOKEN;
    const providedToken = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
    if (!expectedToken || providedToken !== expectedToken) return new Response(null, { status: 404 });
    try {
      if (request.method === 'GET') {
        const sourceGameDay = Number(url.searchParams.get('sourceGameDay'));
        if (!Number.isInteger(sourceGameDay) || sourceGameDay < 1) return Response.json({ ok: false, error: 'sourceGameDay must be a positive integer' }, { status: 400 });
        const result = await withRepository(env, (repository) => getV5CapacityBackfillRun(repository, sourceGameDay));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const body = await request.json() as { runId?: string; sourceGameDay?: number; batchSize?: number };
      if (!body.runId || !Number.isInteger(body.sourceGameDay) || body.sourceGameDay < 1) return Response.json({ ok: false, error: 'runId and positive sourceGameDay are required' }, { status: 400 });
      const result = await withRepository(env, (repository) => backfillV5CapacityBatch(repository, { runId: body.runId!, sourceGameDay: body.sourceGameDay!, batchSize: body.batchSize }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 capacity backfill failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/pantheon' && request.method === 'GET') {
    try {
      const search = url.searchParams.get('search')?.trim();
      const limit = Number(url.searchParams.get('limit') ?? 100);
      const result = await withRepository(env, (repository) => listPantheonOfAchievementsPostgres(repository, { search, limit }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Pantheon fetch failed' }, { status: 500 });
    }
  }

  if (url.pathname === '/api/cemetery' && request.method === 'GET') {
    const search = url.searchParams.get('search')?.trim();
    const house = url.searchParams.get('house')?.trim();
    const dynasty = url.searchParams.get('dynasty')?.trim();
    const limit = Number(url.searchParams.get('limit') ?? 50);
    try {
      const result = await withRepository(env, (repository) =>
        listCemeteryProfilesPostgres(repository, { search, house, dynasty, limit }),
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
