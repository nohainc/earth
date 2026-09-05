import { DurableObject } from 'cloudflare:workers';
import { authorityMode, withRepository } from './repository';
import { cancelMarketOrder as cancelMarketOrderPostgres, listMarketOrders as listMarketOrdersPostgres, settleMarket as settleMarketPostgres, submitMarketOrder as submitMarketOrderPostgres } from './market-postgres';
import { declarePersonalInsolvency as declarePersonalInsolvencyPostgres, publicSpending as publicSpendingPostgres, recoverInstitution as recoverInstitutionPostgres, settleTax as settleTaxPostgres } from './finance-postgres';
import { getLifeStatus as getLifeStatusPostgres, getSuccessor as getSuccessorPostgres, liquidateExpiredEstates as liquidateExpiredEstatesPostgres, registerSuccessor as registerSuccessorPostgres, settleInheritance as settleInheritancePostgres } from './lifecycle-postgres';
import { adoptTechnology as adoptTechnologyPostgres, createResearchProject as createResearchProjectPostgres, fundResearchProject as fundResearchProjectPostgres } from './technology-postgres';
import { castVote as castVotePostgres, challengeProposal as challengeProposalPostgres, createProposal as createProposalPostgres, executeProposal as executeProposalPostgres, resolveConstitutionalAppeal as resolveConstitutionalAppealPostgres, resolveProposals as resolveProposalsPostgres } from './governance-postgres';
import { worldSnapshot as worldSnapshotPostgres } from './world-postgres';
import { advanceWorld as advanceWorldPostgres } from './scheduler-postgres';
import { listAssistants as listAssistantsPostgres, updateAssistantPolicy as updateAssistantPolicyPostgres, upgradeAssistant as upgradeAssistantPostgres } from './ai-postgres';
import { changeCommunityMembership as changeCommunityMembershipPostgres, contributeToCommunity as contributeToCommunityPostgres, createCommunity as createCommunityPostgres, decideCommunityMembershipRequest as decideCommunityMembershipRequestPostgres, disbandCommunity as disbandCommunityPostgres, listCommunities as listCommunitiesPostgres, listCommunityContributions as listCommunityContributionsPostgres, listCommunityMembers as listCommunityMembersPostgres, listCommunityMembershipRequests as listCommunityMembershipRequestsPostgres, setCommunityMemberRole as setCommunityMemberRolePostgres, updateCommunity as updateCommunityPostgres } from './communities-postgres';
import { deliverOutbox } from './outbox-postgres';
import { adoptCityForCorporation as adoptCityForCorporationPostgres, changeCityResidency as changeCityResidencyPostgres, changeCorporationMembership as changeCorporationMembershipPostgres, cityQualification as cityQualificationPostgres, corporationQualification as corporationQualificationPostgres, contributeToCorporation as contributeToCorporationPostgres, createCity as createCityPostgres, createCorporation as createCorporationPostgres, createCorporationWithCapital as createCorporationWithCapitalPostgres, decideCorporationMembershipRequest as decideCorporationMembershipRequestPostgres, listCities as listCitiesPostgres, listCorporations as listCorporationsPostgres, setCityBudget as setCityBudgetPostgres, setCityTaxCharter as setCityTaxCharterPostgres, setCorporationAdmissionPolicy as setCorporationAdmissionPolicyPostgres, setCorporationTaxCharter as setCorporationTaxCharterPostgres, spendCorporationTreasury as spendCorporationTreasuryPostgres } from './institutions-postgres';
import { auditWorld as auditWorldPostgres, getServiceStatus as getServiceStatusPostgres, listCemeteryProfiles as listCemeteryProfilesPostgres, listEvents as listEventsPostgres, listGovernanceProposals as listGovernanceProposalsPostgres, listGovernanceRules as listGovernanceRulesPostgres, listHistory as listHistoryPostgres, listInstitutions as listInstitutionsPostgres, listMarketPriceHistory as listMarketPriceHistoryPostgres, listMembershipEvents as listMembershipEventsPostgres, listNotifications as listNotificationsPostgres, listPantheonOfAchievements as listPantheonOfAchievementsPostgres, listProductionEvents as listProductionEventsPostgres, listOwnershipEvents as listOwnershipEventsPostgres, listRankings as listRankingsPostgres, listTechnology as listTechnologyPostgres, markAllNotificationsRead as markAllNotificationsReadPostgres, markNotificationRead as markNotificationReadPostgres } from './read-postgres';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation';
import { currentHuman, sensitiveActionAllowed } from './auth-session';
import { healthResponse } from './health';
import { authenticatedAuthRoute } from './auth-routes';
import { isPublicAuthMutation, publicAuthRoute } from './auth-public-routes';
import { communicationsRoutes } from './communications-routes';
import { getHouseOverview, unlockHousePerk, equipHouseHeirloom, forgeHouseHeirloom, updateHouseMotto } from './house-postgres.ts';
import { listCommodityDerivativesAndOHLC, createFuturesListing, matchFuturesContract, cancelFuturesListing } from './derivatives-postgres.ts';
import { getNetWorthHistory, recordDailyNetWorthSnapshot } from './net-worth-postgres.ts';
import { getDailyBriefing } from './daily-briefing-postgres.ts';
import { listSocialDirectory } from './social-directory-postgres.ts';
import { purchasePrivatePlotAndConstruct, upgradeBuilding, completeBuildingConstruction, setBuildingOperatingPolicy, setBuildingAutoRepair, repairBuilding, demolishBuilding, getCityDistrictZoning, contributeCorporateResearch } from './real-estate-postgres.ts';
import { BUILDING_CATALOG } from './real-estate-catalog.ts';
import { handleAiRoutes } from './ai-routes.ts';
import { handleHouseRoutes } from './house-routes.ts';
import { handleReadModelRoutes } from './read-model-routes.ts';
import { handleFinanceRoutes } from './finance-routes.ts';
import { handleCommunityRoutes } from './community-routes.ts';
import { handleInstitutionRoutes } from './institutions-routes.ts';
import { getResourceLedgerHistory, getResourceDailyBreakdown, getResourceRateHistory, type ResourceKind, type ExtendedResourceKind } from './resource-ledger-postgres.ts';
import { logAppError, listRecentAppErrors } from './error-logger-postgres.ts';

const WEB_ASSET_VERSION = '2026-08-15-auth-recovery-1';

export class MarketCoordinator extends DurableObject<Env> {
  private sseControllers: Set<ReadableStreamDefaultController<Uint8Array>> = new Set();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      await ctx.storage.put('initialized', true);
    });
  }

  async submitCommand(payload: unknown): Promise<{ ok: true; coordinator: string }> {
    await this.ctx.storage.put('lastCommand', { payload, at: new Date().toISOString() });
    return { ok: true, coordinator: 'market' };
  }

  async snapshot(): Promise<unknown> {
    return this.ctx.storage.get('lastCommand');
  }

  async broadcast(event: Record<string, unknown>): Promise<void> {
    const message = JSON.stringify(event);
    for (const socket of this.ctx.getWebSockets()) {
      try { socket.send(message); } catch { socket.close(1011, 'Live channel unavailable'); }
    }
    const encoder = new TextEncoder();
    const sseChunk = encoder.encode(`data: ${message}\n\n`);
    for (const controller of this.sseControllers) {
      try {
        controller.enqueue(sseChunk);
      } catch {
        this.sseControllers.delete(controller);
      }
    }
  }

  async fetch(request: Request): Promise<Response> {
    const isWebSocket = request.headers.get('Upgrade')?.toLowerCase() === 'websocket';
    const acceptsSSE = request.headers.get('Accept')?.includes('text/event-stream') || new URL(request.url).searchParams.get('format') === 'sse';

    if (isWebSocket) {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      server.send(JSON.stringify({ type: 'ready', channel: 'earth-world', coordinator: 'market' }));
      return new Response(null, { status: 101, webSocket: client });
    }

    if (acceptsSSE || request.method === 'GET') {
      const encoder = new TextEncoder();
      let streamController: ReadableStreamDefaultController<Uint8Array>;
      const stream = new ReadableStream<Uint8Array>({
        start: (controller) => {
          streamController = controller;
          this.sseControllers.add(controller);
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'ready', channel: 'earth-world', coordinator: 'market' })}\n\n`));
        },
        cancel: () => {
          if (streamController) this.sseControllers.delete(streamController);
        },
      });

      return new Response(stream, {
        status: 200,
        headers: {
          'Content-Type': 'text/event-stream; charset=utf-8',
          'Cache-Control': 'no-cache, no-transform',
          'Connection': 'keep-alive',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    return new Response('WebSocket upgrade or SSE request required', { status: 426 });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const text = typeof message === 'string' ? message : new TextDecoder().decode(message);
    if (text === 'ping') {
      socket.send(JSON.stringify({ type: 'pong', at: new Date().toISOString() }));
      return;
    }
    socket.send(JSON.stringify({ type: 'snapshot', data: await this.snapshot() }));
  }

  async webSocketClose(socket: WebSocket, code: number, reason: string): Promise<void> {
    socket.close(code, reason);
  }
}

async function productionEventsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 30)));
  return Response.json({ events: [], limit, persistence: 'planetscale-postgres' });
}

async function servicesStatusFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const city = (await withRepository(env, (repository) => repository.query<Record<string, number>>('SELECT cities.* FROM cities JOIN memberships ON memberships.city_id = cities.id WHERE memberships.human_id = $1', [viewer.id])))?.rows[0];
  const independentBaseline = { housing: 0.75, utilities: 0.75, connectivity: 0.75, health: 0.5 };
  const ratios = city ? { housing: Math.min(1, Number(city.housing_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), utilities: Math.min(1, Number(city.energy_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), connectivity: Math.min(1, Number(city.connectivity_capacity ?? 0) / Math.max(1, Number(city.residents ?? 0))), health: Math.min(1, Number(city.health_capacity ?? 0) / 100) } : independentBaseline;
  const status = Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= 0.75 ? 'basic' : 'critical']));
  return Response.json({ cityId: city?.id ?? null, provider: city ? 'city-capacity' : 'ouc-independent-minimum', ratios, status, essentialServicesIndex: Math.min(...Object.values(ratios)), persistence: 'planetscale-postgres' });
}

async function worldActivityFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, async (repository) => {
    const [world, technology] = await Promise.all([
      repository.query('SELECT game_day, market_batch_seconds FROM world_state WHERE id = $1', ['WORLD']),
      repository.query('SELECT progress FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewer.id]),
    ]);
    return { activity: [{ type: 'world_clock', day: world.rows[0]?.game_day ?? 184 }, { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 }, { type: 'market_cycle', batch: world.rows[0]?.market_batch_seconds ?? 498 }] };
  });
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function eventsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function notificationsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listNotificationsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function markNotificationReadFromPostgres(request: Request, env: Env, notificationId: string): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, (repository) => markNotificationReadPostgres(repository, viewer.id, notificationId));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function markAllNotificationsReadFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, (repository) => markAllNotificationsReadPostgres(repository, viewer.id));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function auditFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, (repository) => auditWorldPostgres(repository, viewer.id));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function institutionsFromPostgres(request: Request, env: Env): Promise<Response> {
  const result = await withRepository(env, (repository) => listInstitutionsPostgres(repository));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function rankingsFromPostgres(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const category = url.searchParams.get('category') ?? undefined;
  const metric = url.searchParams.get('metric') ?? undefined;
  const search = url.searchParams.get('search') ?? undefined;
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
  const offset = Math.max(0, Number(url.searchParams.get('offset') ?? 0));
  const result = await withRepository(env, (repository) => listRankingsPostgres(repository, { category, metric, search, limit, offset }));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function historyFromPostgres(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listHistoryPostgres(repository, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function ownershipHistoryFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listOwnershipEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

async function membershipHistoryFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listMembershipEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get('Origin') ?? '*';
    const corsHeaders = {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Requested-With, X-Request-ID, X-Earth-API-Version, Accept, Cache-Control',
      'Access-Control-Expose-Headers': 'X-Earth-API-Version, X-Request-ID',
      'Access-Control-Allow-Credentials': 'true',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    let response: Response;
    try {
      response = await this.handleRequest(request, env);
      if (response.status >= 500) {
        const viewer = await currentHuman(request, env).catch(() => null);
        const url = new URL(request.url);
        await withRepository(env, (repo) =>
          logAppError(repo, {
            humanId: viewer?.id ?? null,
            source: 'backend_api',
            endpoint: url.pathname,
            statusCode: response.status,
            errorMessage: `API responded with HTTP ${response.status}`,
          }),
        ).catch(() => undefined);
      }
    } catch (err) {
      const viewer = await currentHuman(request, env).catch(() => null);
      const url = new URL(request.url);
      const errorMessage = err instanceof Error ? err.message : String(err);
      const stackTrace = err instanceof Error ? err.stack : undefined;
      await withRepository(env, (repo) =>
        logAppError(repo, {
          humanId: viewer?.id ?? null,
          source: 'backend_api',
          endpoint: url.pathname,
          statusCode: 500,
          errorMessage,
          stackTrace,
        }),
      ).catch(() => undefined);
      console.error(JSON.stringify({ event: 'unhandled_api_error', endpoint: url.pathname, message: errorMessage, stack: stackTrace }));
      response = Response.json({ ok: false, error: errorMessage || 'Internal Server Error', code: 'SERVICE_UNAVAILABLE' }, { status: 500 });
    }

    const newHeaders = new Headers(response.headers);
    for (const [key, value] of Object.entries(corsHeaders)) {
      newHeaders.set(key, value);
    }
    newHeaders.set('X-Earth-API-Version', '2026-08');
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: newHeaders,
    });
  },

  async handleRequest(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Authentication routes must be dispatched before the legacy fallback
    // handler. Without this, /api/auth/login and /api/auth/me fell through to
    // the generic `edge-ready` response: login appeared successful, but no
    // session was actually created or validated for subsequent requests.
    if (isPublicAuthMutation(url.pathname)) {
      const response = await publicAuthRoute(request, env, url);
      if (response) return response;
    }
    const authenticatedResponse = await authenticatedAuthRoute(request, env, url);
    if (authenticatedResponse) return authenticatedResponse;

    // These feature routers were split out of this legacy handler but were
    // not wired back into the dispatch chain. The fallback response is still
    // HTTP 200, which made the client render empty lists instead of exposing
    // a routing error.
    if (url.pathname.startsWith('/api/communities')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const response = await handleCommunityRoutes(request, env, url, viewer);
      if (response) return response;
    }
    if (url.pathname.startsWith('/api/cities') || url.pathname.startsWith('/api/corporations')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const response = await handleInstitutionRoutes(request, env, url, viewer);
      if (response) return response;
    }
    if (url.pathname.startsWith('/api/comm/')) {
      const response = await communicationsRoutes(request, env, url);
      if (response) return response;
    }

    // The world snapshot is the canonical payload consumed by the Flutter
    // command center. Returning the generic edge-ready response here leaves
    // every state-backed page with empty collections despite HTTP 200.
    if (url.pathname === '/api/world' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) =>
        worldSnapshotPostgres(repository, viewer.id),
      );
      if (!result) throw new Error('PostgreSQL repository is unavailable');
      return Response.json(result);
    }

    if (url.pathname === '/api/telemetry/error' && request.method === 'POST') {
      const viewer = await currentHuman(request, env).catch(() => null);
      const parsed = await parseJsonBody<{
        message?: string;
        stack?: string;
        endpoint?: string;
        errorCode?: string;
        statusCode?: number;
        context?: Record<string, unknown>;
        source?: string;
      }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const errorMessage = body.message?.trim() || 'Client error';
      try {
        const logged = await withRepository(env, (repo) =>
          logAppError(repo, {
            humanId: viewer?.id ?? null,
            source: (body.source as any) || 'client_flutter',
            endpoint: body.endpoint ?? null,
            statusCode: body.statusCode ?? null,
            errorCode: body.errorCode ?? null,
            errorMessage,
            stackTrace: body.stack ?? null,
            contextData: body.context ?? {},
          }),
        );
        return Response.json({ ok: true, id: logged?.id });
      } catch (err) {
        return Response.json({ ok: false, error: 'Failed to record error log' }, { status: 500 });
      }
    }
    if (url.pathname === '/api/telemetry/errors' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Number(url.searchParams.get('limit') || 50);
      const offset = Number(url.searchParams.get('offset') || 0);
      const source = url.searchParams.get('source') || undefined;
      const humanId = url.searchParams.get('all') === 'true' ? undefined : (url.searchParams.get('humanId') || viewer.id);
      try {
        const errors = await withRepository(env, (repo) =>
          listRecentAppErrors(repo, { limit, offset, source, humanId }),
        );
        return Response.json({ ok: true, errors: errors ?? [] });
      } catch (err) {
        return Response.json({ ok: false, error: 'Failed to fetch error logs' }, { status: 500 });
      }
    }
    if (url.pathname === '/api/technology' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => listTechnologyPostgres(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/technology/adopt' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ technologyId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const technologyId = parsed.value.technologyId?.trim();
      if (!technologyId) return Response.json({ ok: false, error: 'Technology is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => adoptTechnologyPostgres(repository, { humanId: viewer.id, technologyId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Technology adoption failed' }, { status: 409 });
      }
    }
    if (url.pathname === '/api/technology/projects' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; budget?: number; focus?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const name = body.name?.trim();
      const budget = Math.round(Number(body.budget ?? 240) * 100) / 100;
      const focus = body.focus?.trim() ?? 'efficiency';
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!name || name.length < 3 || name.length > 120 || !Number.isFinite(budget) || budget < 240 || budget > 100000 || !['efficiency','durability','safety','cost'].includes(focus) || !correlationId) return Response.json({ ok: false, error: 'Research parameters or Idempotency-Key are invalid' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createResearchProjectPostgres(repository, { ownerId: viewer.id, name, budget, focus, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Research project creation failed' }, { status: 409 });
      }
    }
    if ((url.pathname === '/api/technology/TECH-001/fund' || url.pathname === '/api/technology/me/fund') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const amount = Number(body.amount ?? 240);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(amount) || amount <= 0 || !correlationId) return Response.json({ ok: false, error: 'Funding parameters or Idempotency-Key are invalid' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => fundResearchProjectPostgres(repository, { ownerId: viewer.id, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Research funding failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, async (repository) => {
        const [account, state, buildings] = await Promise.all([
          repository.query("SELECT account_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
          repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
          repository.query("SELECT id, name, status FROM buildings WHERE owner_id = $1 AND ownership_class = 'private'", [viewer.id]),
        ]);
        const stateRow = state.rows[0] ?? { status: 'active', protected_credits: 100 };
        return { account: account.rows[0] ?? null, state: stateRow, liquidatableAssets: { buildings: buildings.rows }, protectedMinimum: { credits: Number(stateRow.protected_credits ?? 100), basicServiceRobot: true } };
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/finance/personal/declare' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ otp?: string; reason?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for personal insolvency' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => declarePersonalInsolvencyPostgres(repository, viewer.id, (body.reason?.trim() || 'Human-requested insolvency restructuring').slice(0, 240)));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Personal insolvency failed' }, { status: 409 });
      }
    }

    if (url.pathname === '/api/finance' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, async (repository) => {
        const [account, rules] = await Promise.all([
          repository.query("SELECT account_id, owner_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
          repository.query('SELECT scope, category, rate, version FROM tax_rules WHERE active = true ORDER BY id'),
        ]);
        return { account: account.rows[0] ?? null, taxRules: rules.rows };
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }

    if (url.pathname === '/api/finance/liquidity' && request.method === 'GET') {
      const liquidity = (await withRepository(env, (repository) => repository.query<{ active_humans: number; money_supply: string; living_cost_index: string }>("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index")))?.rows[0];
      const activeHumans = Number(liquidity?.active_humans ?? 0); const supply = Number(liquidity?.money_supply ?? 0); const livingCostIndex = Number(liquidity?.living_cost_index ?? 1); const target = activeHumans * Math.max(0.5, livingCostIndex) * 100;
      return Response.json({ activeHumans, moneySupply: supply, livingCostIndex, target, corridor: { low: target * 0.8, high: target * 1.2 }, status: supply < target * 0.8 ? 'below-corridor' : supply > target * 1.2 ? 'above-corridor' : 'inside-corridor', persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/finance/status' && request.method === 'GET') {
      const result = await withRepository(env, async (repository) => {
        const [states, events] = await Promise.all([
          repository.query('SELECT * FROM financial_states ORDER BY status DESC, institution_kind, institution_id'),
          repository.query('SELECT * FROM bankruptcy_events ORDER BY game_day DESC, created_at DESC LIMIT 50'),
        ]);
        return { states: states.rows, events: events.rows };
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }

    // ── House / dynasty routes → house-routes.ts ────────────────────────────
    const houseResponse = await handleHouseRoutes(request, env, url);
    if (houseResponse) return houseResponse;

    if (url.pathname === '/api/market/derivatives' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      const commodity = url.searchParams.get('commodity') || 'energy';
      const humanId = viewer?.id || 'H-0044';
      try {
        const result = await withRepository(env, (repository) => listCommodityDerivativesAndOHLC(repository, commodity, humanId));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to fetch derivatives';
        return Response.json({ ok: false, error: message }, { status: 400 });
      }
    }

    if (url.pathname === '/api/market/futures/create' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ commodity?: string; size?: number; strikePrice?: number; durationGameMinutes?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const commodity = parsed.value.commodity?.toLowerCase().trim() ?? 'energy';
      const size = Number(parsed.value.size);
      const strikePrice = Number(parsed.value.strikePrice);
      const durationGameMinutes = Number(parsed.value.durationGameMinutes);
      const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);

      try {
        const result = await withRepository(env, (repository) => createFuturesListing(repository, {
          sellerId: viewer.id,
          commodity,
          size,
          strikePrice,
          durationGameMinutes,
          correlationId,
        }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Futures creation failed';
        return Response.json({ ok: false, error: message }, { status: /insufficient/i.test(message) ? 409 : 400 });
      }
    }

    if (url.pathname.startsWith('/api/market/futures/') && url.pathname.endsWith('/buy') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const segments = url.pathname.split('/');
      const contractId = segments[4];
      if (!contractId) return Response.json({ ok: false, error: 'Contract ID is required' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request);

      try {
        const result = await withRepository(env, (repository) => matchFuturesContract(repository, {
          buyerId: viewer.id,
          contractId,
          correlationId,
        }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Futures matching failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : (/insufficient/i.test(message) ? 409 : 400) });
      }
    }

    if (url.pathname.startsWith('/api/market/futures/') && url.pathname.endsWith('/cancel') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const segments = url.pathname.split('/');
      const contractId = segments[4];
      if (!contractId) return Response.json({ ok: false, error: 'Contract ID is required' }, { status: 400 });

      try {
        const result = await withRepository(env, (repository) => cancelFuturesListing(repository, {
          sellerId: viewer.id,
          contractId,
        }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Futures cancellation failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 400 });
      }
    }

    if (url.pathname === '/api/finance/net-worth-history' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      const humanId = viewer?.id || 'H-0044';
      try {
        const result = await withRepository(env, (repository) => getNetWorthHistory(repository, humanId));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to fetch net-worth history';
        return Response.json({ ok: false, error: message }, { status: 400 });
      }
    }

    if (url.pathname === '/api/player/daily-briefing' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      const humanId = viewer?.id || 'H-0044';
      try {
        const result = await withRepository(env, (repository) => getDailyBriefing(repository, humanId));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to generate daily briefing';
        return Response.json({ ok: false, error: message }, { status: 400 });
      }
    }
    if (url.pathname === '/api/finance/recover' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ institutionId?: string; amount?: number; otp?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for financial recovery' }, { status: 401 });
      const institutionId = body.institutionId?.trim() ?? '';
      const amount = Math.round(Number(body.amount) * 100) / 100;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!institutionId || !Number.isFinite(amount) || amount <= 0 || amount > 100000 || !correlationId) return Response.json({ ok: false, error: 'Recovery amount must be between 0 and 100,000 Credits' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => recoverInstitutionPostgres(repository, { humanId: viewer.id, institutionId, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Institution recovery failed';
        return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient|crisis/i.test(message) ? 409 : 400 });
      }
    }
    if (url.pathname === '/api/taxes/settle' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ taxableAmount?: number }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const taxableAmount = Number(body.taxableAmount);
      if (!Number.isFinite(taxableAmount) || taxableAmount <= 0) return Response.json({ ok: false, error: 'Taxable amount must be positive' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => settleTaxPostgres(repository, viewer.id, taxableAmount));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Tax settlement failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    if (url.pathname === '/api/finance/public-spending' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ cityId?: string; category?: string; amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const cityId = body.cityId || 'CITY-0084';
      const category = body.category?.trim() || 'public-services';
      const amount = Number(body.amount);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(amount) || amount <= 0 || !correlationId) return Response.json({ ok: false, error: 'Public spending amount and Idempotency-Key are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => publicSpendingPostgres(repository, { actorId: viewer.id, cityId, category, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Public spending failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    if (url.pathname === '/api/market/book' && request.method === 'GET') {
      const result = await withRepository(env, async (repository) => {
        const [rows, trades, rule] = await Promise.all([
          repository.query("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product"),
          repository.query('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product'),
          repository.query("SELECT rate FROM tax_rules WHERE scope = 'global' AND category = 'market' AND active = true LIMIT 1"),
        ]);
        const feeRate = Number(rule.rows[0]?.rate ?? 0);
        return { book: rows.rows, trades: trades.rows, feeRate };
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listMarketOrdersPostgres(repository, url.searchParams.get('product')));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ product?: string; quantity?: number; limitPrice?: number; side?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const product = body.product;
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = Number(body.quantity);
      const limitPrice = Number(body.limitPrice);
      if (!['food', 'material', 'components', 'energy', 'compute'].includes(product ?? '') || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0) return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => submitMarketOrderPostgres(repository, { humanId: viewer.id, product: product!, side, quantity, limitPrice, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Market order failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient|reservation/i.test(message) ? 409 : 400 });
      }
    }
    const cancelOrderMatch = url.pathname.match(/^\/api\/market\/orders\/([^/]+)$/);
    if (cancelOrderMatch && request.method === 'DELETE') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => cancelMarketOrderPostgres(repository, { orderId: cancelOrderMatch[1], humanId: viewer.id }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market order cancellation failed' }, { status: 404 });
      }
    }
    if (url.pathname === '/api/market/settle' && request.method === 'POST') {
      const parsed = await parseJsonBody<{ product?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const product = body.product;
      if (!['food', 'material', 'components', 'energy', 'compute'].includes(product ?? '')) return Response.json({ ok: false, error: 'Unknown product' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => settleMarketPostgres(repository, product!));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market settlement failed' }, { status: 409 });
      }
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'GET') {
      await withRepository(env, (repository) => resolveProposalsPostgres(repository));
      const result = await withRepository(env, (repository) => listGovernanceProposalsPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/governance/rules' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listGovernanceRulesPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ institutionId?: string; title?: string; body?: string; durationHours?: number; ruleVersionId?: string; target?: { category?: string; value?: Record<string, unknown> }; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const institutionId = body.institutionId?.trim() || 'OUC-001';
      const title = body.title?.trim();
      const proposalBody = body.body?.trim();
      if (!title || title.length < 8 || title.length > 140) return Response.json({ ok: false, error: 'Proposal title must be 8–140 characters' }, { status: 400 });
      if (!proposalBody || proposalBody.length < 20 || proposalBody.length > 4000) return Response.json({ ok: false, error: 'Proposal body must be 20–4000 characters' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      const targetCategory = body.target?.category?.trim() || null;
      if (targetCategory && !['market', 'finance', 'services', 'technology', 'megaproject_procurement'].includes(targetCategory)) return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createProposalPostgres(repository, { humanId: human.id, institutionId, title, body: proposalBody, durationHours: body.durationHours, ruleVersionId: body.ruleVersionId, targetCategory, targetValue: body.target?.value ?? null, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Proposal creation failed' }, { status: 409 });
      }
    }
    const voteMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/vote$/);
    if (voteMatch && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ vote?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => castVotePostgres(repository, { proposalId: voteMatch[1], humanId: human.id, choice: body.vote! }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Ballot failed';
        return Response.json({ ok: false, error: message }, { status: /already/i.test(message) ? 409 : /not found/i.test(message) ? 404 : 403 });
      }
    }
    const executeProposalMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/execute$/);
    if (executeProposalMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => executeProposalPostgres(repository, { proposalId: executeProposalMatch[1], humanId: viewer.id }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Proposal execution failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    const challengeProposalMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/challenge$/);
    if (challengeProposalMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ reason?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const reason = body.reason?.trim() ?? 'Constitutional appeal filed during delay window';
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => challengeProposalPostgres(repository, { humanId: viewer.id, proposalId: challengeProposalMatch[1], reason, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Constitutional challenge failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    const appealRulingMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/appeal-ruling$/);
    if (appealRulingMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ ruling?: string; rationale?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const ruling = body.ruling === 'void' ? 'void' : 'uphold';
      const rationale = body.rationale?.trim() ?? 'High Court appeal determination';
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => resolveConstitutionalAppealPostgres(repository, { humanId: viewer.id, proposalId: appealRulingMatch[1], ruling, rationale, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Appeal resolution failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    if (url.pathname === '/api/pantheon' && request.method === 'GET') {
      try {
        const result = await withRepository(env, (repository) => listPantheonOfAchievementsPostgres(repository));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Pantheon fetch failed' }, { status: 500 });
      }
    }
    if (url.pathname === '/api/cemetery' && request.method === 'GET') {
      const search = url.searchParams.get('search')?.trim();
      const dynasty = url.searchParams.get('dynasty')?.trim();
      const limit = Number(url.searchParams.get('limit') ?? 50);
      try {
        const result = await withRepository(env, (repository) => listCemeteryProfilesPostgres(repository, { search, dynasty, limit }));
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
    // Businesses were removed in favor of direct Human ownership. Keep the
    // old namespace closed so stale clients receive a deterministic response.
    if (url.pathname === '/api/businesses' || url.pathname.startsWith('/api/businesses/')) {
      return Response.json({ ok: false, error: 'Business entities are no longer supported; use Human-owned assets' }, { status: 410 });
    }

    if (url.pathname === '/api/life/successor' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => getSuccessorPostgres(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/life/status' && request.method === 'GET') {
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => getLifeStatusPostgres(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/life/successor' && request.method === 'POST') {
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; estatePeriodDays?: number; successorHumanId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const successorName = (body.name ?? '').trim();
      if (!successorName) {
        const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, { humanId: viewer.id, successorName: '', estatePeriodDays: 30, successorHumanId: null, currentLifeStatus: viewer.life_status }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const estatePeriodDays = Number(body.estatePeriodDays ?? 30);
      if (!Number.isInteger(estatePeriodDays) || estatePeriodDays < 7 || estatePeriodDays > 90) return Response.json({ ok: false, error: 'Estate period must be between 7 and 90 days' }, { status: 400 });
      const successorHumanId = body.successorHumanId?.trim() || null;
      try {
        if (viewer.life_status === 'estate') {
          if (!successorHumanId) return Response.json({ ok: false, error: 'An Estate Period requires an existing active Successor Human' }, { status: 400 });
          const world = await withRepository(env, (repository) => repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'"));
          const day = Number(world?.rows[0]?.game_day ?? 0);
          const result = await withRepository(env, (repository) => settleInheritancePostgres(repository, { predecessorId: viewer.id, successorId: successorHumanId, successorName, day }));
          if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
          return Response.json({ ...result, persistence: 'planetscale-postgres' });
        }
        const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, { humanId: viewer.id, successorName, estatePeriodDays, successorHumanId, currentLifeStatus: viewer.life_status }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Successor registration failed';
        return Response.json({ ok: false, error: message }, { status: /another active/i.test(message) ? 400 : 409 });
      }
    }
    return Response.json({ service: 'earth-world', environment: env.ENVIRONMENT, status: 'edge-ready' });
  },
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    const result = await withRepository(env, async (repository) => {
      await resolveProposalsPostgres(repository);
      // One real minute advances one game hour: a game day is 24 real minutes.
      const world = await advanceWorldPostgres(repository, 60, String(_event.scheduledTime));
      await repository.query('UPDATE world_state SET last_scheduler_at = to_timestamp($1 / 1000.0) WHERE id = \'WORLD\'', [_event.scheduledTime]);
      const outboxDelivered = await deliverOutbox(repository, (outboxEvent) =>
        env.MARKET_COORDINATOR.getByName('events-global').broadcast({
          ...outboxEvent.payload,
          id: outboxEvent.id,
          eventKey: outboxEvent.event_key,
          topic: outboxEvent.topic,
          aggregateType: outboxEvent.aggregate_type,
          aggregateId: outboxEvent.aggregate_id,
        }),
      );
      return { ...world, outboxDelivered };
    });
    if (!result) throw new Error('PostgreSQL repository is unavailable for scheduled world advancement');
    await env.MARKET_COORDINATOR.getByName('events-global').broadcast({
      type: result.newDay ? 'world_day_started' : 'world_tick',
      gameDay: result.day,
      gameMinute: result.minute,
      productionEvents: result.productionEvents,
      marketSettlements: result.marketSettlements,
      at: new Date().toISOString(),
    });
  },
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const requestId = request.headers.get('X-Request-ID') || crypto.randomUUID();
    const origin = request.headers.get('Origin');
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': origin ?? '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Request-ID, X-Requested-With, X-Earth-API-Version, Accept, Cache-Control',
          'Access-Control-Expose-Headers': 'X-Request-ID, X-EARTH-API-Version',
          'Access-Control-Allow-Credentials': 'true',
          'Access-Control-Max-Age': '86400',
          'Vary': 'Origin',
          'X-Request-ID': requestId,
        },
      });
    }
    const url = new URL(request.url);
    if (url.pathname.startsWith('/building-assets/')) {
      const key = url.pathname.slice('/building-assets/'.length);
      if (!key || key.includes('..') || key.includes('\\')) {
        return new Response('Not found', { status: 404 });
      }
      const object = await env.BUILDING_ASSETS.get(key);
      if (!object) return new Response('Not found', { status: 404 });
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('cache-control', 'public, max-age=31536000, immutable');
      headers.set('etag', object.httpEtag);
      return new Response(object.body, { headers });
    }
    const isDataRequest = url.pathname.startsWith('/api/') || url.pathname.startsWith('/edge/') || url.pathname === '/health' || url.pathname === '/ready' || url.pathname === '/api/ready';
    let response: Response;
    try {
      if (isDataRequest) authorityMode(env);
      if (isDataRequest) {
        const readModelResponse = await handleReadModelRoutes(request, env, url);
        if (readModelResponse) {
          response = readModelResponse;
        } else if (url.pathname === '/api/production/events' && request.method === 'GET') {
          response = await productionEventsFromPostgres(request, env);
        } else if (url.pathname === '/api/services/status' && request.method === 'GET') {
          response = await servicesStatusFromPostgres(request, env);
        } else {
          response = await worker.fetch(request, env, ctx);
        }
      } else if (url.pathname === '/' || url.pathname === '/landing') {
        response = await env.ASSETS.fetch(new Request(new URL('/landing.html', request.url), request));
      } else if (url.pathname === '/app' || url.pathname === '/app/') {
        response = await env.ASSETS.fetch(new Request(new URL('/app.html', request.url), request));
      } else if (url.pathname.startsWith('/app/')) {
        const assetSubpath = url.pathname.slice(4);
        response = await env.ASSETS.fetch(new Request(new URL(assetSubpath + url.search, request.url), request));
      } else {
        response = await env.ASSETS.fetch(request);
      }
      if ((request.method === 'POST' || request.method === 'DELETE') && response.status < 400 && url.pathname.startsWith('/api/')) {
        const deliverPromise = withRepository(env, (repository) =>
          deliverOutbox(repository, (outboxEvent) =>
            env.MARKET_COORDINATOR.getByName('events-global').broadcast({
              ...outboxEvent.payload,
              id: outboxEvent.id,
              eventKey: outboxEvent.event_key,
              topic: outboxEvent.topic,
              aggregateType: outboxEvent.aggregate_type,
              aggregateId: outboxEvent.aggregate_id,
            }),
          ),
        ).catch((err) => {
          console.error(JSON.stringify({ event: 'outbox_dispatch_error', error: err instanceof Error ? err.message : String(err) }));
        });
        if (ctx && typeof ctx.waitUntil === 'function') {
          ctx.waitUntil(deliverPromise);
        }
      }
    } catch (error) {
      console.error(JSON.stringify({ event: 'worker_request_failed', requestId, path: url.pathname, method: request.method, error: error instanceof Error ? error.message : 'unknown' }));
      const malformedJson = error instanceof SyntaxError && /json|unexpected end|unexpected token/i.test(error.message);
      response = malformedJson
        ? Response.json({ ok: false, error: 'Request body must be valid JSON object', code: 'VALIDATION_ERROR', correlationId: requestId }, { status: 400 })
        : Response.json({ ok: false, error: 'EARTH service is temporarily unavailable', code: 'SERVICE_UNAVAILABLE', correlationId: requestId }, { status: 503 });
    }
    const headers = new Headers(response.headers);
    if (origin) {
      headers.set('Access-Control-Allow-Origin', origin);
      headers.set('Access-Control-Allow-Credentials', 'true');
      headers.set('Vary', 'Origin');
    } else {
      headers.set('Access-Control-Allow-Origin', '*');
    }
    headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, Idempotency-Key, X-Request-ID, X-Requested-With, X-Earth-API-Version, Accept, Cache-Control');
    headers.set('Access-Control-Expose-Headers', 'X-Request-ID, X-EARTH-API-Version');
    headers.set('X-Request-ID', requestId);
    headers.set('X-EARTH-API-Version', '2026-08');

    const acceptHeader = request.headers.get('Accept') ?? '';
    const requestContentType = request.headers.get('Content-Type') ?? '';
    const prefersNano = acceptHeader.includes('application/nanomarkup') ||
      requestContentType.includes('application/nanomarkup');

    const isJsonResponse = response.headers.get('content-type')?.includes('application/json') ||
      response.headers.get('content-type')?.includes('application/nanomarkup');

    if (isJsonResponse) {
      try {
        let payload: Record<string, unknown> | null = null;
        try {
          payload = await response.clone().json() as Record<string, unknown>;
        } catch {
          // not json
        }
        if (payload && typeof payload === 'object') {
          if (response.status >= 400) {
            const codeByStatus: Record<number, string> = {
              400: 'VALIDATION_ERROR',
              401: 'AUTHENTICATION_REQUIRED',
              403: 'FORBIDDEN',
              404: 'NOT_FOUND',
              409: 'CONFLICT',
              429: 'RATE_LIMITED',
              500: 'INTERNAL_ERROR',
              503: 'SERVICE_UNAVAILABLE',
            };
            if (typeof payload.code !== 'string' || !payload.code) payload.code = codeByStatus[response.status] ?? 'REQUEST_FAILED';
            if (typeof payload.correlationId !== 'string' || !payload.correlationId) payload.correlationId = requestId;
          }

          if (prefersNano) {
            headers.set('content-type', 'application/nanomarkup; charset=utf-8');
            return new Response(toNanoMarkup(payload), { status: response.status, statusText: response.statusText, headers });
          } else {
            headers.set('content-type', 'application/json');
            return new Response(JSON.stringify(payload), { status: response.status, statusText: response.statusText, headers });
          }
        }
      } catch {
        // Preserve non-JSON or malformed error responses unchanged.
      }
    }
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  },
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    return worker.scheduled(event, env, ctx);
  },
};
