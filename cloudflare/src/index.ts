import { DurableObject } from 'cloudflare:workers';
import { authorityMode, withRepository } from './repository';
import { getLifeStatus as getLifeStatusPostgres, getSuccessor as getSuccessorPostgres, registerSuccessor as registerSuccessorPostgres } from './lifecycle-postgres';
import { createResearchProject as createResearchProjectPostgres, fundResearchProject as fundResearchProjectPostgres } from './technology-postgres';
import { worldSnapshot as worldSnapshotPostgres } from './world-postgres';
import { runSchedulerHeartbeat } from './scheduler';
import { deliverOutbox } from './outbox-postgres';
import { getServiceStatus as getServiceStatusPostgres, listTechnology as listTechnologyPostgres } from './read-postgres';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation';
import { currentHuman, currentViewer, sensitiveActionAllowed } from './auth-session';
import { healthResponse, livenessResponse } from './health';
import { authenticatedAuthRoute } from './auth-routes';
import { isPublicAuthMutation, publicAuthRoute } from './auth-public-routes';
import { communicationsRoutes } from './communications-routes';
import { handleHouseRoutes } from './house-routes.ts';
import { handleReadModelRoutes } from './read-model-routes.ts';
import { handleFinanceRoutes } from './finance-routes.ts';
import { handleCommunityRoutes } from './community-routes.ts';
import { handleInstitutionRoutes } from './institutions-routes.ts';
import { handleOrganizationRoutes } from './organizations-routes.ts';
import { handleGovernanceRoutes } from './governance-routes.ts';
import { handleRealEstateRoutes } from './real-estate-routes.ts';
import { logBackendError, logClientError, sanitizeClientContext } from './observability.ts';
import { handleEconomicRoutes } from './economic-routes.ts';
import { handleMarketApiRoutes } from './market-api.ts';
import { featureConfig, featureDisabledResponse, featureEnabled } from './feature-config.ts';
import { maintenanceModeEnabled, maintenanceResponse, schedulerEnabled } from './maintenance.ts';
import { handleRealtimeRoute, mapToRealtimeInvalidation } from './realtime.ts';
import { errorResponse, earthError } from './errors.ts';

const WEB_ASSET_VERSION = '2026-08-15-auth-recovery-1';

function corsOriginFor(request: Request, env: Env): string | null {
  const configured = String((env as unknown as Record<string, unknown>).CORS_ORIGIN ?? 'https://earthuc.com')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const requestOrigin = request.headers.get('Origin');
  if (!requestOrigin) return null;
  const requestHost = new URL(request.url).hostname;
  const localWorkerHost = requestHost === 'localhost' || requestHost === '127.0.0.1' || requestHost === '::1' || requestHost === '[::1]';
  if (localWorkerHost) return requestOrigin;
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
      server.send(JSON.stringify({ version: 1, type: 'ready', topics: ['world', 'market', 'house', 'finance', 'buildings', 'research', 'governance', 'notifications', 'institutions', 'communities'], channel: 'earth-world', coordinator: 'market' }));
      return new Response(null, { status: 101, webSocket: client });
    }

    if (acceptsSSE || request.method === 'GET') {
      const encoder = new TextEncoder();
      let streamController: ReadableStreamDefaultController<Uint8Array>;
      const stream = new ReadableStream<Uint8Array>({
        start: (controller) => {
          streamController = controller;
          this.sseControllers.add(controller);
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ version: 1, type: 'ready', topics: ['world', 'market', 'house', 'finance', 'buildings', 'research', 'governance', 'notifications', 'institutions', 'communities'], channel: 'earth-world', coordinator: 'market' })}\n\n`));
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
      socket.send(JSON.stringify({ version: 1, type: 'pong', at: new Date().toISOString() }));
      return;
    }
    socket.send(JSON.stringify({
      version: 1,
      type: 'refresh_required',
      topics: ['world'],
      reason: 'market_state_is_postgres_authoritative',
    }));
  }

  async webSocketClose(_socket: WebSocket, _code: number, _reason: string): Promise<void> {
    // The runtime has already closed (or is closing) this socket. In
    // particular, code 1006 is diagnostic-only and must never be sent.
  }
}

async function servicesStatusFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const result = await withRepository(env, (repository) => getServiceStatusPostgres(repository, viewer.id));
  if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
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
        logBackendError({
          requestId: request.headers.get('X-Request-ID'),
          humanId: viewer?.id ?? null,
          endpoint: url.pathname,
          statusCode: response.status,
          message: `API responded with HTTP ${response.status}`,
        });
      }
    } catch (err) {
      const viewer = await currentHuman(request, env).catch(() => null);
      const url = new URL(request.url);
      response = errorResponse(err, request.headers.get('X-Request-ID'), 'EARTH service is temporarily unavailable.', { requestId: request.headers.get('X-Request-ID'), endpoint: url.pathname });
    }

    if ((response as Response & { webSocket?: WebSocket }).webSocket) return response;
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
    if (maintenanceModeEnabled(env) && (
      url.pathname === '/api/ready' || url.pathname === '/ready' ||
      url.pathname === '/api/health' || url.pathname === '/health'
    )) return maintenanceResponse();
    if (url.pathname === '/api/ready' || url.pathname === '/ready') {
      return healthResponse(request, env, { readiness: true });
    }
    if (url.pathname === '/api/health' || url.pathname === '/health') {
      return healthResponse(request, env);
    }
    if (maintenanceModeEnabled(env)) return maintenanceResponse();

    const realtimeResponse = await handleRealtimeRoute(request, env, url);
    if (realtimeResponse) return realtimeResponse;

    // Authentication routes are dispatched before the remaining route groups
    // handler. Without this, /api/auth/login and /api/auth/me fell through to
    // the generic `edge-ready` response: login appeared successful, but no
    // session was actually created or validated for subsequent requests.
    if (isPublicAuthMutation(url.pathname)) {
      const response = await publicAuthRoute(request, env, url);
      if (response) return response;
    }
    const authenticatedResponse = await authenticatedAuthRoute(request, env, url);
    if (authenticatedResponse) return authenticatedResponse;

    // Feature routers are composed explicitly here so an unhandled API path
    // reaches the canonical 404 response instead of a fake success response.
    if (url.pathname.startsWith('/api/communities')) {
      const viewer = await currentViewer(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const response = await handleCommunityRoutes(request, env, url, viewer, sensitiveActionAllowed);
      if (response) return response;
    }
    if (url.pathname.startsWith('/api/organizations')) {
      const viewer = await currentViewer(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const response = await handleOrganizationRoutes(request, env, url, viewer);
      if (response) return response;
    }
    if (url.pathname.startsWith('/api/corporations')) {
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
        worldSnapshotPostgres(repository, viewer.id, viewer.house_id),
      );
      if (!result) throw new Error('PostgreSQL repository is unavailable');
      return Response.json(result);
    }

    if (url.pathname === '/api/telemetry/error' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
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
      logClientError({
        requestId: request.headers.get('X-Request-ID'),
        humanId: viewer.id,
        endpoint: body.endpoint,
        statusCode: body.statusCode,
        errorCode: body.errorCode,
        message: body.message,
        stack: body.stack,
        context: sanitizeClientContext(body.context),
        clientVersion: request.headers.get('X-Earth-Client-Version'),
      });
      return new Response(null, { status: 202 });
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
      const budget = Math.round(Number(body.budget) * 100) / 100;
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
      const amount = Number(body.amount);
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
    if (maintenanceModeEnabled(env) || !schedulerEnabled(env)) {
      console.log(JSON.stringify({ event: 'scheduler_skipped_maintenance_mode' }));
      return;
    }
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
        env.MARKET_COORDINATOR.getByName('events-global').broadcast(mapToRealtimeInvalidation(outboxEvent)),
      ), { workload: 'scheduler' }) ?? 0;
    } catch (error) {
      console.error('Scheduler outbox delivery failed after committed economy work', error);
    }
    // Baseline 001 intentionally keeps scheduler_runs minimal. Outbox delivery
    // is observable from event_outbox itself; do not write legacy projection
    // columns that are not part of the canonical scheduler schema.
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
    const isDataRequest = !healthPath && (url.pathname.startsWith('/api/') || url.pathname.startsWith('/internal/'));
    let response: Response;
    try {
      if (healthPath) {
        // Health endpoints are Worker routes and must not depend on the
        // optional static-assets binding used by the browser shell.
        response = await worker.handleRequest(request, env);
      } else if (isDataRequest) authorityMode(env);
      if (healthPath) {
        // Handled above.
      } else if (isDataRequest) {
        const readModelResponse = await handleReadModelRoutes(request, env, url);
        if (readModelResponse) {
          response = readModelResponse;
        } else if (url.pathname.startsWith('/api/governance')) {
          const viewer = await currentHuman(request, env);
          if (!viewer) response = Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
          else response = await handleGovernanceRoutes(request, env, url, viewer) ?? await worker.handleRequest(request, env);
        } else if (url.pathname === '/api/services/status' && request.method === 'GET') {
          response = await servicesStatusFromPostgres(request, env);
        } else {
          response = await worker.handleRequest(request, env);
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
            env.MARKET_COORDINATOR.getByName('events-global').broadcast(mapToRealtimeInvalidation(outboxEvent)),
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
        ? errorResponse(earthError('VALIDATION_ERROR', 'Request body must be valid JSON object.'), requestId)
        : errorResponse(error, requestId, 'EARTH service is temporarily unavailable.', { requestId, endpoint: url.pathname });
    }
    if ((response as Response & { webSocket?: WebSocket }).webSocket) return response;
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
