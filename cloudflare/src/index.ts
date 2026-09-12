import { DurableObject } from 'cloudflare:workers';
import { authorityMode, withRepository } from './repository';
import { getLifeStatus as getLifeStatusPostgres, getSuccessor as getSuccessorPostgres, registerSuccessor as registerSuccessorPostgres } from './lifecycle-postgres';
import { createResearchProject as createResearchProjectPostgres, fundResearchProject as fundResearchProjectPostgres } from './technology-postgres';
import { worldSnapshot as worldSnapshotPostgres } from './world-postgres';
import { runSchedulerHeartbeat } from './scheduler';
import { changeCommunityMembership as changeCommunityMembershipPostgres, contributeToCommunity as contributeToCommunityPostgres, createCommunity as createCommunityPostgres, decideCommunityMembershipRequest as decideCommunityMembershipRequestPostgres, disbandCommunity as disbandCommunityPostgres, listCommunities as listCommunitiesPostgres, listCommunityContributions as listCommunityContributionsPostgres, listCommunityMembers as listCommunityMembersPostgres, listCommunityMembershipRequests as listCommunityMembershipRequestsPostgres, setCommunityMemberRole as setCommunityMemberRolePostgres, updateCommunity as updateCommunityPostgres } from './communities-postgres';
import { deliverOutbox } from './outbox-postgres';
import { listTechnology as listTechnologyPostgres } from './read-postgres';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation';
import { currentHuman, sensitiveActionAllowed } from './auth-session';
import { healthResponse, livenessResponse } from './health';
import { authenticatedAuthRoute } from './auth-routes';
import { isPublicAuthMutation, publicAuthRoute } from './auth-public-routes';
import { communicationsRoutes } from './communications-routes';
import { handleHouseRoutes } from './house-routes.ts';
import { handleReadModelRoutes } from './read-model-routes.ts';
import { handleFinanceRoutes } from './finance-routes.ts';
import { handleCommunityRoutes } from './community-routes.ts';
import { handleInstitutionRoutes } from './institutions-routes.ts';
import { handleGovernanceRoutes } from './governance-routes.ts';
import { handleRealEstateRoutes } from './real-estate-routes.ts';
import { logAppError, listRecentAppErrors } from './error-logger-postgres.ts';
import { handleEconomicRoutes } from './economic-routes.ts';
import { handleMarketApiRoutes } from './market-api.ts';
import { featureConfig, featureDisabledResponse, featureEnabled } from './feature-config.ts';

const WEB_ASSET_VERSION = '2026-08-15-auth-recovery-1';

function corsOriginFor(request: Request, env: Env): string | null {
  const configured = String((env as unknown as Record<string, unknown>).CORS_ORIGIN ?? 'https://earthuc.com')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const requestOrigin = request.headers.get('Origin');
  if (!requestOrigin) return null;
  return configured.includes(requestOrigin) ? requestOrigin : null;
}

export class MarketCoordinator extends DurableObject<Env> {
  private sseControllers: Set<ReadableStreamDefaultController<Uint8Array>> = new Set();

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
    socket.send(JSON.stringify({
      type: 'refresh_required',
      reason: 'market_state_is_postgres_authoritative',
    }));
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
  const result = await withRepository(env, (repository) => repository.query(
    `SELECT j.id, j.building_id, j.city_id, j.day AS game_day,
            j.actual_output_units, j.service_capacity_units, j.operating_expense_units,
            j.status_after
       FROM building_settlement_journals j
       JOIN buildings b ON b.id = j.building_id
      WHERE j.day = (SELECT game_day FROM world_state WHERE id = 'WORLD')
        AND (b.owner_id = $1 OR b.city_id IN (SELECT city_id FROM memberships WHERE human_id = $1))
      ORDER BY j.id DESC LIMIT $2`, [viewer.id, limit]));
  if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
  return Response.json({ events: result.rows, limit, persistence: 'planetscale-postgres' });
}

async function servicesStatusFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, async (repository) => {
    const city = await repository.query<{ id: string }>('SELECT city_id AS id FROM memberships WHERE human_id = $1 AND city_id IS NOT NULL LIMIT 1', [viewer.id]);
    const cityId = city.rows[0]?.id;
    if (!cityId) return { cityId: null, projection: null };
    const projection = await repository.query('SELECT * FROM city_service_capacity_daily WHERE city_id = $1 ORDER BY game_day DESC LIMIT 1', [cityId]);
    return { cityId, projection: projection.rows[0] ?? null };
  });
  if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
  const projection = result.projection as Record<string, number> | null;
  const ratios = projection ? {
    housing: Number(projection.coverage_ratio ?? 0),
    utilities: Number(projection.energy_capacity ?? 0) / Math.max(1, Number(projection.service_demand ?? 0)),
    connectivity: Number(projection.connectivity_capacity ?? 0) / Math.max(1, Number(projection.service_demand ?? 0)),
    health: Number(projection.health_capacity ?? 0) / Math.max(1, Number(projection.service_demand ?? 0)),
  } : { housing: 0, utilities: 0, connectivity: 0, health: 0 };
  for (const key of Object.keys(ratios)) ratios[key as keyof typeof ratios] = Math.min(1, Math.max(0, ratios[key as keyof typeof ratios]));
  const status = Object.fromEntries(Object.entries(ratios).map(([key, value]) => [key, value >= 1 ? 'normal' : value >= 0.75 ? 'basic' : 'critical']));
  return Response.json({ cityId: result.cityId, provider: projection ? 'city-service-capacity-projection' : null, ratios, status, essentialServicesIndex: Math.min(...Object.values(ratios)), persistence: 'planetscale-postgres' });
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = corsOriginFor(request, env);
    const corsHeaders = {
      ...(origin ? { 'Access-Control-Allow-Origin': origin } : {}),
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Requested-With, X-Request-ID, X-Earth-API-Version, Accept, Cache-Control',
      'Access-Control-Expose-Headers': 'X-Earth-API-Version, X-Request-ID',
      ...(origin ? { 'Access-Control-Allow-Credentials': 'true' } : {}),
      'Vary': 'Origin',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
      'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
    };

    if (request.method === 'OPTIONS') {
      if (request.headers.get('Origin') && !origin) return new Response(null, { status: 403, headers: corsHeaders });
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

    if (url.pathname === '/api/live') return livenessResponse(request);
    if (url.pathname === '/api/ready' || url.pathname === '/ready') {
      return healthResponse(request, env, { readiness: true });
    }
    if (url.pathname === '/api/health' || url.pathname === '/health') {
      return healthResponse(request, env);
    }

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
    if (url.pathname.startsWith('/api/real-estate') || url.pathname.startsWith('/api/research/')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const response = await handleRealEstateRoutes(request, env, url, viewer);
      if (response) return response;
    }
    if (url.pathname.startsWith('/api/finance')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const response = await handleFinanceRoutes(request, env, url, viewer, (targetEnv, humanId, otp) => sensitiveActionAllowed(targetEnv, humanId, otp));
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
      // Error telemetry is a player-scoped diagnostic surface. Do not allow a
      // query parameter to turn it into an unauthorised cross-player/admin
      // data export.
      const humanId = viewer.id;
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
    if (url.pathname === '/api/technology/me/fund' && request.method === 'POST') {
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
    if (url.pathname === '/api/economy' || url.pathname.startsWith('/api/economy/')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const economicRoute = await handleEconomicRoutes(request, env, url, viewer);
      if (economicRoute) return economicRoute;
    }

    // ── House / dynasty routes → house-routes.ts ────────────────────────────
    const houseResponse = await handleHouseRoutes(request, env, url);
    if (houseResponse) return houseResponse;

    const marketApiResponse = await handleMarketApiRoutes(request, env, url);
    if (marketApiResponse) return marketApiResponse;

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
      if (!featureEnabled(env, 'mortality')) return featureDisabledResponse('mortality');
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const successorName = (body.name ?? '').trim();
      if (!successorName) {
        const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, { humanId: viewer.id, successorName: '', currentLifeStatus: viewer.life_status }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      try {
        const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, { humanId: viewer.id, successorName, currentLifeStatus: viewer.life_status }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Successor registration failed';
        return Response.json({ ok: false, error: message }, { status: /another active/i.test(message) ? 400 : 409 });
      }
    }
    return Response.json({ ok: false, error: 'API route not found', code: 'NOT_FOUND' }, { status: 404 });
  },
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    const result = await withRepository(env, async (repository) => {
      // One real minute advances one game hour: a game day is 24 real minutes.
      const schedulerConfig = env as unknown as Record<string, unknown>;
      const world = await runSchedulerHeartbeat(repository, _event.scheduledTime, {
        maxCatchupDays: schedulerConfig.EARTH_SCHEDULER_MAX_CATCHUP_DAYS,
        workBudgetMs: schedulerConfig.EARTH_SCHEDULER_WORK_BUDGET_MS,
        features: featureConfig(env),
      });
      return world;
    }, { workload: 'scheduler' });
    if (!result) throw new Error('PostgreSQL repository is unavailable for scheduled world advancement');
    let outboxDelivered = 0;
    try {
      outboxDelivered = await withRepository(env, (repository) => deliverOutbox(repository, (outboxEvent) =>
        env.MARKET_COORDINATOR.getByName('events-global').broadcast({
          ...outboxEvent.payload,
          id: outboxEvent.id,
          eventKey: outboxEvent.event_key,
          topic: outboxEvent.topic,
          aggregateType: outboxEvent.aggregate_type,
          aggregateId: outboxEvent.aggregate_id,
        }),
      ), { workload: 'scheduler' }) ?? 0;
    } catch (error) {
      console.error('Scheduler outbox delivery failed after committed economy work', error);
    }
    await withRepository(env, (repository) => repository.query(
      'UPDATE scheduler_runs SET outbox_events_delivered = $2 WHERE id = $1',
      [result.schedulerRunId, outboxDelivered],
    ), { workload: 'scheduler' }).catch(() => undefined);
    const completedResult = { ...result, outboxDelivered };
    await env.MARKET_COORDINATOR.getByName('events-global').broadcast({
      type: completedResult.newDay ? 'world_day_started' : 'world_tick',
      gameDay: completedResult.day,
      gameMinute: completedResult.minute,
      productionEvents: completedResult.productionEvents,
      marketSettlements: completedResult.marketSettlements,
      at: new Date().toISOString(),
    });
  },
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const requestId = request.headers.get('X-Request-ID') || crypto.randomUUID();
    const origin = corsOriginFor(request, env);
    if (request.method === 'OPTIONS') {
      if (request.headers.get('Origin') && !origin) return new Response(null, { status: 403, headers: { 'Vary': 'Origin' } });
      return new Response(null, {
        status: 204,
        headers: {
          ...(origin ? { 'Access-Control-Allow-Origin': origin } : {}),
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Request-ID, X-Requested-With, X-Earth-API-Version, Accept, Cache-Control',
          'Access-Control-Expose-Headers': 'X-Request-ID, X-EARTH-API-Version',
          ...(origin ? { 'Access-Control-Allow-Credentials': 'true' } : {}),
          'Access-Control-Max-Age': '86400',
          'Vary': 'Origin',
          'X-Request-ID': requestId,
        },
      });
    }
    const url = new URL(request.url);
    if (url.pathname.startsWith('/media/')) {
      const key = url.pathname.slice('/media/'.length);
      if (!key || key.includes('..') || key.includes('\\')) {
        return new Response('Not found', { status: 404 });
      }
      const mediaBucket = (env as any).MEDIA ?? (env as any).BUILDING_ASSETS;
      const object = mediaBucket ? await mediaBucket.get(key) : null;
      if (!object) return new Response('Not found', { status: 404 });
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('cache-control', 'public, max-age=31536000, immutable');
      headers.set('etag', object.httpEtag);
      return new Response(object.body, { headers });
    }
    if (url.pathname.startsWith('/building-assets/')) {
      const key = url.pathname.slice('/building-assets/'.length);
      if (!key || key.includes('..') || key.includes('\\')) {
        return new Response('Not found', { status: 404 });
      }
      const mediaBucket = (env as any).MEDIA ?? (env as any).BUILDING_ASSETS;
      const object = mediaBucket ? (await mediaBucket.get(key) ?? await mediaBucket.get(`buildings/${key}`)) : null;
      if (!object) return new Response('Not found', { status: 404 });
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('cache-control', 'public, max-age=31536000, immutable');
      headers.set('etag', object.httpEtag);
      return new Response(object.body, { headers });
    }
    const healthPath = url.pathname === '/api/live' || url.pathname === '/api/ready' || url.pathname === '/ready' || url.pathname === '/api/health' || url.pathname === '/health';
    const isDataRequest = !healthPath && (url.pathname.startsWith('/api/') || url.pathname.startsWith('/edge/') || url.pathname.startsWith('/internal/'));
    let response: Response;
    try {
      if (isDataRequest) authorityMode(env);
      if (isDataRequest) {
        const readModelResponse = await handleReadModelRoutes(request, env, url);
        if (readModelResponse) {
          response = readModelResponse;
        } else if (url.pathname.startsWith('/api/governance')) {
          const viewer = await currentHuman(request, env);
          if (!viewer) response = Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
          else response = await handleGovernanceRoutes(request, env, url, viewer) ?? await worker.fetch(request, env, ctx);
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
      headers.delete('Access-Control-Allow-Origin');
      headers.delete('Access-Control-Allow-Credentials');
    }
    headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, Idempotency-Key, X-Request-ID, X-Requested-With, X-Earth-API-Version, Accept, Cache-Control');
    headers.set('Access-Control-Expose-Headers', 'X-Request-ID, X-EARTH-API-Version');
    headers.set('X-Request-ID', requestId);
    headers.set('X-EARTH-API-Version', '2026-08');
    headers.set('X-Content-Type-Options', 'nosniff');
    headers.set('X-Frame-Options', 'DENY');
    headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
    headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');

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
