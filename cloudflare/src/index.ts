import { DurableObject } from 'cloudflare:workers';
import { authorityMode, withRepository } from './repository';
import { cancelMarketOrder as cancelMarketOrderPostgres, listMarketOrders as listMarketOrdersPostgres, settleMarket as settleMarketPostgres, submitMarketOrder as submitMarketOrderPostgres } from './market-postgres';
import { declarePersonalInsolvency as declarePersonalInsolvencyPostgres, publicSpending as publicSpendingPostgres, recoverInstitution as recoverInstitutionPostgres, settleTax as settleTaxPostgres } from './finance-postgres';
import { getLifeStatus as getLifeStatusPostgres, getSuccessor as getSuccessorPostgres, liquidateExpiredEstates as liquidateExpiredEstatesPostgres, registerSuccessor as registerSuccessorPostgres, settleInheritance as settleInheritancePostgres } from './lifecycle-postgres';
import { acceptContract as acceptContractPostgres, cancelContract as cancelContractPostgres, createContract as createContractPostgres, openDispute as openDisputePostgres } from './contracts-postgres';
import { resolveContractDispute as resolveContractDisputePostgres } from './arbitration-postgres';
import { appointManager as appointManagerPostgres, createBusiness as createBusinessPostgres, dismissEmployee as dismissEmployeePostgres, distributeDividends as distributeDividendsPostgres, executeMerger as executeMergerPostgres, hireEmployee as hireEmployeePostgres, issueShares as issueSharesPostgres, liquidateBusiness as liquidateBusinessPostgres, ownershipRegistry as ownershipRegistryPostgres, proposeMerger as proposeMergerPostgres, setPolicy as setBusinessPolicyPostgres, trainEmployee as trainEmployeePostgres, transferShares as transferSharesPostgres, updateConstitution as updateConstitutionPostgres } from './business-postgres';
import { acquireMachine as acquireMachinePostgres, maintainMachine as maintainMachinePostgres, sellMachine as sellMachinePostgres, setMachineUtilization as setMachineUtilizationPostgres, upgradeMachine as upgradeMachinePostgres } from './machines-postgres';
import { recycleMachine as recycleMachinePostgres } from './machines-recycling-postgres';
import { createResearchProject as createResearchProjectPostgres, fundResearchProject as fundResearchProjectPostgres, grantPatent as grantPatentPostgres, licenseTechnology as licenseTechnologyPostgres } from './technology-postgres';
import { castVote as castVotePostgres, challengeProposal as challengeProposalPostgres, createProposal as createProposalPostgres, executeProposal as executeProposalPostgres, resolveConstitutionalAppeal as resolveConstitutionalAppealPostgres, resolveProposals as resolveProposalsPostgres } from './governance-postgres';
import { advanceWorld as advanceWorldPostgres } from './scheduler-postgres';
import { worldSnapshot as worldSnapshotPostgres } from './world-postgres';
import { listAssistants as listAssistantsPostgres, updateAssistantPolicy as updateAssistantPolicyPostgres, upgradeAssistant as upgradeAssistantPostgres } from './ai-postgres';
import { changeDelegation as changeDelegationPostgres, changeRole as changeRolePostgres, listRoles as listRolesPostgres } from './roles-postgres';
import { changeCommunityMembership as changeCommunityMembershipPostgres, contributeToCommunity as contributeToCommunityPostgres, createCommunity as createCommunityPostgres, listCommunities as listCommunitiesPostgres, listCommunityContributions as listCommunityContributionsPostgres, listCommunityMembers as listCommunityMembersPostgres } from './communities-postgres';
import { deliverOutbox } from './outbox-postgres';
import { adoptCityForCorporation as adoptCityForCorporationPostgres, changeCityResidency as changeCityResidencyPostgres, changeCorporationMembership as changeCorporationMembershipPostgres, cityQualification as cityQualificationPostgres, corporationQualification as corporationQualificationPostgres, contributeToCorporation as contributeToCorporationPostgres, createCity as createCityPostgres, createCorporation as createCorporationPostgres, listCities as listCitiesPostgres, listCorporations as listCorporationsPostgres, setCityBudget as setCityBudgetPostgres, setCityTaxCharter as setCityTaxCharterPostgres, setCorporationTaxCharter as setCorporationTaxCharterPostgres, spendCorporationTreasury as spendCorporationTreasuryPostgres } from './institutions-postgres';
import { auditWorld as auditWorldPostgres, getServiceStatus as getServiceStatusPostgres, listAuthorityEvents as listAuthorityEventsPostgres, listCemeteryProfiles as listCemeteryProfilesPostgres, listEvents as listEventsPostgres, listGovernanceProposals as listGovernanceProposalsPostgres, listGovernanceRules as listGovernanceRulesPostgres, listHistory as listHistoryPostgres, listInstitutions as listInstitutionsPostgres, listMarketPriceHistory as listMarketPriceHistoryPostgres, listMembershipEvents as listMembershipEventsPostgres, listNotifications as listNotificationsPostgres, listPantheonOfAchievements as listPantheonOfAchievementsPostgres, listProductionEvents as listProductionEventsPostgres, listOwnershipEvents as listOwnershipEventsPostgres, listRankings as listRankingsPostgres, listTechnology as listTechnologyPostgres, markNotificationRead as markNotificationReadPostgres, readBusiness as readBusinessPostgres, readBusinessProfile as readBusinessProfilePostgres } from './read-postgres';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation';
import { MACHINE_CATALOG, productionCatalogResponse } from './production-catalog';
import { currentHuman, sensitiveActionAllowed } from './auth-session';
import { healthResponse } from './health';
import { authenticatedAuthRoute } from './auth-routes';
import { communicationsRoutes } from './communications-routes';
import { listSupplyContracts, proposeSupplyContract, acceptSupplyContract, cancelSupplyContract, getContractDeliveryTicks } from './supply-contracts-postgres.ts';
import { getDynastyOverview, unlockDynastyPerk, equipDynastyHeirloom, forgeDynastyHeirloom, updateDynastyMotto } from './dynasty-postgres.ts';
import { listCommodityDerivativesAndOHLC, createFuturesListing, matchFuturesContract, cancelFuturesListing } from './derivatives-postgres.ts';
import { getNetWorthHistory, recordDailyNetWorthSnapshot } from './net-worth-postgres.ts';
import { getDailyBriefing } from './daily-briefing-postgres.ts';
import { createSocialInitiative, listSocialInitiatives, listSocialDirectory, listSocialTimeline, listSocialRelationships, respondToSocialInitiative, contributeToSocialInitiative, type SocialKind } from './social-gameplay-postgres.ts';
import { getEmailDeliveriesPostgres } from './admin-deliveries-postgres.ts';
import { isPublicAuthMutation, publicAuthRoute } from './auth-public-routes';
import { toNanoMarkup } from './nano-markup.ts';

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

async function advanceWorldFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  try {
    const result = await withRepository(env, async (repository) => {
      await resolveProposalsPostgres(repository);
      return advanceWorldPostgres(repository, 1440);
    });
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    const state = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewer.id));
    return Response.json({ ok: true, result, state, persistence: 'planetscale-postgres' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to advance the simulation clock';
    return Response.json({ ok: false, error: message }, { status: 409 });
  }
}

async function productionEventsFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 30)));
  const result = await withRepository(env, (repository) => repository.query('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = $1 ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT $2', [viewer.id, limit]));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ events: result.rows, persistence: 'planetscale-postgres' });
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

async function authorityHistoryFromPostgres(request: Request, env: Env): Promise<Response> {
  const viewer = await currentHuman(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  const url = new URL(request.url);
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
  const result = await withRepository(env, (repository) => listAuthorityEventsPostgres(repository, viewer.id, limit));
  if (!result) throw new Error('PostgreSQL repository is unavailable');
  return Response.json({ ...result, persistence: 'planetscale-postgres' });
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get('Origin') ?? '*';
    const corsHeaders = {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Requested-With, X-Request-ID, X-Earth-API-Version, Accept',
      'Access-Control-Expose-Headers': 'X-Earth-API-Version, X-Request-ID',
      'Access-Control-Allow-Credentials': 'true',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const response = await this.handleRequest(request, env);
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
    if (url.pathname === '/api/day/advance' && request.method === 'POST') return advanceWorldFromPostgres(request, env);
    if (url.pathname === '/api/production/events' && request.method === 'GET') return productionEventsFromPostgres(request, env);
    if (url.pathname === '/api/services/status' && request.method === 'GET') return servicesStatusFromPostgres(request, env);
    if (url.pathname === '/api/world/activity' && request.method === 'GET') return worldActivityFromPostgres(request, env);
    if (url.pathname === '/api/events' && request.method === 'GET') return eventsFromPostgres(request, env);
    if (url.pathname === '/api/notifications' && request.method === 'GET') return notificationsFromPostgres(request, env);
    if (url.pathname === '/api/audit' && request.method === 'GET') return auditFromPostgres(request, env);
    const notificationReadRoute = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
    if (notificationReadRoute && request.method === 'POST') return markNotificationReadFromPostgres(request, env, notificationReadRoute[1]);
    if (url.pathname === '/api/world/audit' && request.method === 'GET') return auditFromPostgres(request, env);
    if (url.pathname === '/api/institutions' && request.method === 'GET') return institutionsFromPostgres(request, env);
    if (url.pathname === '/api/rankings' && request.method === 'GET') return rankingsFromPostgres(request, env);
    if (url.pathname === '/api/history' && request.method === 'GET') return historyFromPostgres(request, env);
    if (url.pathname === '/api/ownership/events' && request.method === 'GET') return ownershipHistoryFromPostgres(request, env);
    if (url.pathname === '/api/membership/events' && request.method === 'GET') return membershipHistoryFromPostgres(request, env);
    if (url.pathname === '/api/governance/authority/events' && request.method === 'GET') return authorityHistoryFromPostgres(request, env);
    if (url.pathname === '/api/admin/email-deliveries' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => getEmailDeliveriesPostgres(repository, { bindingConfigured: Boolean(env.EMAIL && env.EMAIL_FROM) }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/health/email' && request.method === 'GET') {
      const bindingConfigured = Boolean(env.EMAIL && env.EMAIL_FROM);
      const result = await withRepository(env, (repository) => getEmailDeliveriesPostgres(repository, { limit: 10, bindingConfigured }));
      const ok = bindingConfigured;
      return Response.json({
        ok,
        status: ok ? 'healthy' : 'unconfigured',
        bindingConfigured,
        emailFromConfigured: Boolean(env.EMAIL_FROM),
        recentDeliveries: result?.metrics ?? null,
      });
    }
    const commResponse = await communicationsRoutes(request, env, url);
    if (commResponse) return commResponse;
    if (url.pathname === '/api/social/initiatives' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const initiatives = await withRepository(env, repo => listSocialInitiatives(repo, human.id));
      return Response.json({ ok: true, initiatives: initiatives ?? [] });
    }
    if (url.pathname === '/api/social/directory' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const directory = await withRepository(env, repo => listSocialDirectory(repo, human.id, url.searchParams.get('q') ?? ''));
      return Response.json({ ok: true, ...directory });
    }
    if (url.pathname === '/api/social/relationships' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const relationships = await withRepository(env, repo => listSocialRelationships(repo, human.id));
      return Response.json({ ok: true, relationships: relationships ?? [] });
    }
    if (url.pathname === '/api/social/timeline' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const timeline = await withRepository(env, repo => listSocialTimeline(repo, human.id, Number(url.searchParams.get('limit') ?? 50)));
      return Response.json({ ok: true, timeline: timeline ?? [] });
    }
    if (url.pathname === '/api/social/initiatives' && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ targetId?: string; kind?: SocialKind; title?: string; body?: string; terms?: Record<string, unknown>; gameDay?: number }>(request);
      if (!parsed.ok) return parsed.response;
      const value = parsed.value;
      if (!value.kind || !value.title?.trim() || !value.body?.trim()) return Response.json({ ok: false, error: 'kind, title, and body are required' }, { status: 400 });
      const initiative = await withRepository(env, repo => createSocialInitiative(repo, { creatorId: human.id, targetId: value.targetId, kind: value.kind!, title: value.title!.trim(), body: value.body!.trim(), terms: value.terms, gameDay: value.gameDay }));
      return Response.json({ ok: true, initiative });
    }
    const socialResponse = url.pathname.match(/^\/api\/social\/initiatives\/([^/]+)\/(accept|decline|contribute)$/);
    if (socialResponse && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ contribution?: number }>(request);
      if (!parsed.ok) return parsed.response;
      const result = await withRepository(env, repo => socialResponse[2] === 'contribute'
        ? contributeToSocialInitiative(repo, human.id, socialResponse[1], Number(parsed.value.contribution ?? 1))
        : respondToSocialInitiative(repo, human.id, socialResponse[1], socialResponse[2] === 'accept'));
      return Response.json({ ok: true, initiative: result });
    }
    const authRouteResponse = await authenticatedAuthRoute(request, env, url);
    if (authRouteResponse) return authRouteResponse;
    const publicAuthResponse = await publicAuthRoute(request, env, url);
    if (publicAuthResponse) return publicAuthResponse;
    const publicMutation = isPublicAuthMutation(url.pathname);
    const estateMutation = url.pathname === '/api/life/successor' || url.pathname === '/api/successor';
    if (url.pathname.startsWith('/api/') && request.method === 'POST' && !publicMutation && !(await currentHuman(request, env, estateMutation))) {
      return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    }
    if (url.pathname === '/api/ai' && !(await currentHuman(request, env))) {
      return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    }
    if (url.pathname === '/edge/market') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const stub = env.MARKET_COORDINATOR.getByName('central-market');
      if (request.method === 'POST') {
        const parsed = await parseJsonBody<unknown>(request);
        if (!parsed.ok) return parsed.response;
        return Response.json(await stub.submitCommand({ humanId: human.id, command: parsed.value }));
      }
      return Response.json({ ok: true, coordinator: 'market', state: await stub.snapshot() });
    }
    if (url.pathname === '/edge/events') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const stub = env.MARKET_COORDINATOR.getByName('events-global');
      return stub.fetch(request);
    }
    if (url.pathname === '/api/world' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const viewerId = viewer.id;
      try {
        const snapshot = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewerId));
        if (!snapshot) return Response.json({ ok: false, code: 'WORLD_SNAPSHOT_UNAVAILABLE', error: 'World snapshot is temporarily unavailable', persistence: 'planetscale-postgres' }, { status: 503 });
        return Response.json(snapshot);
      } catch (error) {
        console.error(JSON.stringify({ event: 'world_snapshot_failed', code: 'WORLD_SNAPSHOT_UNAVAILABLE', message: error instanceof Error ? error.message : 'unknown' }));
        return Response.json({ ok: false, code: 'WORLD_SNAPSHOT_UNAVAILABLE', error: 'World snapshot is temporarily unavailable', persistence: 'planetscale-postgres' }, { status: 503 });
      }
    }
    if (url.pathname === '/api/ai' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => listAssistantsPostgres(repository, viewer.id));
      return Response.json({ ...result, constraints: { governance: false, authority: false, allowedPolicies: ['recommend', 'maintenance'] }, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/ai/policy' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ assistantId?: string; policy?: string; enabled?: boolean }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!body.assistantId || !['recommend', 'maintenance'].includes(body.policy ?? '')) return Response.json({ ok: false, error: 'Basic AI supports only recommend or maintenance policies' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => updateAssistantPolicyPostgres(repository, { ownerId: viewer.id, assistantId: body.assistantId, policy: body.policy ?? 'recommend', enabled: body.enabled !== false }));
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'AI assistant not found' }, { status: 404 });
      }
    }
    if (url.pathname === '/api/ai/upgrade' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ assistantId?: string; otp?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for AI upgrade' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => upgradeAssistantPostgres(repository, { ownerId: viewer.id, assistantId: body.assistantId ?? '' }));
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'AI upgrade failed';
        return Response.json({ ok: false, error: message }, { status: /insufficient/i.test(message) ? 409 : 404 });
      }
    }
    if (url.pathname === '/api/health' || url.pathname === '/health' || url.pathname === '/api/ready' || url.pathname === '/ready') return healthResponse(request, env);
    if (url.pathname === '/api/governance/roles' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listRolesPostgres(repository));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    const roleClaimMatch = url.pathname.match(/^\/api\/governance\/roles\/([^/]+)\/(claim|resign)$/);
    if (roleClaimMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => changeRolePostgres(repository, { humanId: viewer.id, roleId: roleClaimMatch[1], action: roleClaimMatch[2] as 'claim' | 'resign' }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Role operation failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /occupied|assignment|eligible|maturity/i.test(message) ? 409 : 403 });
      }
    }
    const delegationMatch = url.pathname.match(/^\/api\/governance\/roles\/([^/]+)\/(delegate|recall)$/);
    if (delegationMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ delegateHumanId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      try {
        const result = await withRepository(env, (repository) => changeDelegationPostgres(repository, { humanId: viewer.id, roleId: delegationMatch[1], action: delegationMatch[2] as 'delegate' | 'recall', delegateHumanId: body.delegateHumanId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Delegation operation failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /occupied|currently|eligible|holder/i.test(message) ? 409 : 403 });
      }
    }
    if (url.pathname === '/api/communities' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listCommunitiesPostgres(repository));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/communities' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; founderId?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const name = body.name?.trim();
      const founderId = viewer.id;
      if (!name || name.length < 3 || name.length > 80) return Response.json({ ok: false, error: 'Community name must be 3–80 characters' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createCommunityPostgres(repository, { founderId, name, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Community formation failed';
        return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /founder/i.test(message) ? 404 : 400 });
      }
    }
    const communityMembersMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/members$/);
    if (communityMembersMatch && request.method === 'GET') {
      const communityId = communityMembersMatch[1];
      try {
        const result = await withRepository(env, (repository) => listCommunityMembersPostgres(repository, communityId));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community members could not be loaded' }, { status: 404 });
      }
    }
    if (communityMembersMatch && (request.method === 'POST' || request.method === 'DELETE')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const communityId = communityMembersMatch[1];
      const humanId = viewer.id;
      try {
        const result = await withRepository(env, (repository) => changeCommunityMembershipPostgres(repository, { communityId, humanId, action: request.method === 'POST' ? 'join' : 'leave' }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: request.method === 'POST' ? 201 : 200 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Community membership change failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member|active/i.test(message) ? 409 : 400 });
      }
    }
    const communityContributionMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/contributions$/);
    if (communityContributionMatch && request.method === 'GET') {
      const communityId = communityContributionMatch[1];
      try {
        const result = await withRepository(env, (repository) => listCommunityContributionsPostgres(repository, communityId));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community contributions could not be loaded' }, { status: 404 });
      }
    }
    if (communityContributionMatch && request.method === 'POST') {
      const communityId = communityContributionMatch[1];
      const authenticatedHuman = await currentHuman(request, env);
      if (!authenticatedHuman) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ humanId?: string; amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const humanId = authenticatedHuman.id;
      const amount = Math.round(Number(body.amount) * 100) / 100;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Contribution amount must be positive' }, { status: 400 });
      if (amount > 100000) return Response.json({ ok: false, error: 'Contribution exceeds the per-command limit' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => contributeToCommunityPostgres(repository, { communityId, humanId, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Community contribution failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient|member|active/i.test(message) ? 409 : 400 });
      }
    }
    if (url.pathname === '/api/cities' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listCitiesPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/cities' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; communityId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const name = body.name?.trim();
      const communityId = body.communityId?.trim();
      if (!name || name.length < 3 || name.length > 80 || !communityId) return Response.json({ ok: false, error: 'City name and founding Community are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createCityPostgres(repository, { founderId: viewer.id, communityId, name }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'City formation failed';
        return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
      }
    }
    const cityQualificationMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/qualification$/);
    if (cityQualificationMatch && request.method === 'GET') {
      try {
        const result = await withRepository(env, (repository) => cityQualificationPostgres(repository, cityQualificationMatch[1]));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'City qualification unavailable' }, { status: 404 });
      }
    }
    if (url.pathname === '/api/corporations' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listCorporationsPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/corporations' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; cityId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const name = body.name?.trim();
      const cityId = body.cityId?.trim();
      if (!name || name.length < 3 || name.length > 80 || !cityId) return Response.json({ ok: false, error: 'Corporation name and founding City are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createCorporationPostgres(repository, { founderId: viewer.id, cityId, name }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Corporation formation failed';
        return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
      }
    }
    const corporationQualificationMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/qualification$/);
    if (corporationQualificationMatch && request.method === 'GET') {
      try {
        const result = await withRepository(env, (repository) => corporationQualificationPostgres(repository, corporationQualificationMatch[1]));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation qualification unavailable' }, { status: 404 });
      }
    }

    const cityBudgetMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/budget$/);
    if (cityBudgetMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ category?: string; amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const category = body.category?.trim();
      const amount = Number(body.amount);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!category || !Number.isFinite(amount) || amount < 0 || !correlationId) return Response.json({ ok: false, error: 'A valid budget category, amount, and correlation ID are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => setCityBudgetPostgres(repository, { humanId: viewer.id, cityId: cityBudgetMatch[1], category, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'City budget update failed';
        return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
      }
    }
    const cityTaxCharterMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/tax-charter$/);
    if (cityTaxCharterMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ incomeTaxBps?: number; salesTaxBps?: number; corporateTaxBps?: number; propertyTaxBps?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => setCityTaxCharterPostgres(repository, { humanId: viewer.id, cityId: cityTaxCharterMatch[1], incomeTaxBps: Number(body.incomeTaxBps ?? 0), salesTaxBps: Number(body.salesTaxBps ?? 0), corporateTaxBps: Number(body.corporateTaxBps ?? 0), propertyTaxBps: Number(body.propertyTaxBps ?? 0), correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Tax charter update failed';
        return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
      }
    }
    const corporationTaxCharterMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/tax-charter$/);
    if (corporationTaxCharterMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ incomeTaxBps?: number; salesTaxBps?: number; corporateTaxBps?: number; propertyTaxBps?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => setCorporationTaxCharterPostgres(repository, { humanId: viewer.id, corporationId: corporationTaxCharterMatch[1], incomeTaxBps: Number(body.incomeTaxBps ?? 0), salesTaxBps: Number(body.salesTaxBps ?? 0), corporateTaxBps: Number(body.corporateTaxBps ?? 0), propertyTaxBps: Number(body.propertyTaxBps ?? 0), correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Corporation tax charter update failed';
        return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
      }
    }
    const corporationCityMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/cities\/([^/]+)$/);
    if (corporationCityMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => adoptCityForCorporationPostgres(repository, { humanId: viewer.id, corporationId: corporationCityMatch[1], cityId: corporationCityMatch[2] }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Corporation city adoption failed';
        return Response.json({ ok: false, error: message }, { status: /required|another corporation|include members/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
      }
    }
    const corporationMembershipMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/membership$/);
    if (corporationMembershipMatch && (request.method === 'POST' || request.method === 'DELETE')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => changeCorporationMembershipPostgres(repository, { humanId: viewer.id, corporationId: corporationMembershipMatch[1], action: request.method === 'POST' ? 'join' : 'leave' }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Corporation membership change failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member/i.test(message) ? 409 : 400 });
      }
    }
    const residencyMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/residency$/);
    if (residencyMatch && (request.method === 'POST' || request.method === 'DELETE')) {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const dayKey = request.method === 'POST' ? '' : 'leave';
      const correlationId = body.correlationId?.trim() || `RESIDENCY-${viewer.id}-${residencyMatch[1]}-${request.method}-${dayKey}`;
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => changeCityResidencyPostgres(repository, { humanId: viewer.id, cityId: residencyMatch[1], action: request.method === 'POST' ? 'join' : 'leave', correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'City residency change failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|resident/i.test(message) ? 409 : 400 });
      }
    }
    const corporationSpendMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/treasury\/spend$/);
    if (corporationSpendMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ category?: string; amount?: number; cityId?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const amount = Number(body.amount);
      const category = body.category?.trim() || 'public-services';
      const cityId = body.cityId?.trim() || 'CITY-0084';
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100000 || !correlationId) return Response.json({ ok: false, error: 'Treasury amount and correlation ID are invalid' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => spendCorporationTreasuryPostgres(repository, { humanId: viewer.id, corporationId: corporationSpendMatch[1], cityId, category, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Corporation treasury spending failed';
        return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient/i.test(message) ? 409 : 400 });
      }
    }
    const corporationContributionMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/contributions$/);
    if (corporationContributionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const amount = Math.round(Number(body.amount) * 100) / 100;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(amount) || amount <= 0 || amount > 10000 || !correlationId) return Response.json({ ok: false, error: 'Contribution amount or correlation ID is invalid' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => contributeToCorporationPostgres(repository, { humanId: viewer.id, corporationId: corporationContributionMatch[1], amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Corporation contribution failed';
        return Response.json({ ok: false, error: message }, { status: /membership|required/i.test(message) ? 403 : /insufficient/i.test(message) ? 409 : 400 });
      }
    }

    if (url.pathname === '/api/machines' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, async (repository) => repository.query('SELECT * FROM machines WHERE owner_id = $1 ORDER BY id', [viewer.id]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ machines: result.rows, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/machines/acquire' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ machineType?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const type = body.machineType?.trim() ?? '';
      const spec = MACHINE_CATALOG[type];
      if (!spec) return Response.json({ ok: false, error: 'Unsupported machine type' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => acquireMachinePostgres(repository, { ownerId: viewer.id, machineType: type, name: `${type.replaceAll('-', ' ')} ${viewer.id.slice(-4)}`, credit: spec.credit, material: spec.material, capacity: spec.capacity, output: spec.output, inputResource: 'energy', correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Machine acquisition failed' }, { status: 409 });
      }
    }
    if (url.pathname === '/api/production/catalog' && request.method === 'GET') {
      return productionCatalogResponse();
    }
    if (url.pathname === '/api/technology' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listTechnologyPostgres(repository));
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
    if ((url.pathname === '/api/technology/TECH-001/patent' || url.pathname === '/api/technology/me/patent') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => grantPatentPostgres(repository, { ownerId: viewer.id }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Patent grant failed' }, { status: 409 });
      }
    }
    if ((url.pathname === '/api/technology/TECH-001/license' || url.pathname === '/api/technology/me/license') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ licenseeId?: string; royaltyRate?: number; licenseFee?: number; otp?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const licenseeId = body.licenseeId || viewer.id;
      const royaltyRate = Number(body.royaltyRate ?? 0.05);
      const licenseFee = Math.round(Number(body.licenseFee ?? (licenseeId === viewer.id ? 0 : 100)) * 100) / 100;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(royaltyRate) || royaltyRate < 0 || royaltyRate > 1 || !Number.isFinite(licenseFee) || licenseFee < 0 || licenseFee > 100000 || (licenseeId !== viewer.id && licenseFee < 50) || !correlationId) return Response.json({ ok: false, error: 'License terms or Idempotency-Key are invalid' }, { status: 400 });
      if (licenseeId !== viewer.id && !(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for external IP licensing' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => licenseTechnologyPostgres(repository, { ownerId: viewer.id, licenseeId, royaltyRate, licenseFee, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Technology license failed' }, { status: 409 });
      }
    }

    if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, async (repository) => {
        const [account, state, machines, businesses] = await Promise.all([
          repository.query("SELECT account_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
          repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
          repository.query("SELECT id, machine_type, condition FROM machines WHERE owner_id = $1 AND machine_type != 'service-robot'", [viewer.id]),
          repository.query('SELECT id, name, status FROM businesses WHERE owner_id = $1', [viewer.id]),
        ]);
        const stateRow = state.rows[0] ?? { status: 'active', protected_credits: 100 };
        return { account: account.rows[0] ?? null, state: stateRow, liquidatableAssets: { machines: machines.rows, businesses: businesses.rows }, protectedMinimum: { credits: Number(stateRow.protected_credits ?? 100), basicServiceRobot: true } };
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

    if (url.pathname === '/api/contracts' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => repository.query("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = $1 OR negotiated_contracts.counterparty_id = $1 ORDER BY negotiated_contracts.created_at DESC LIMIT 50", [viewer.id]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ contracts: result.rows, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/contracts' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ kind?: string; counterpartyId?: string; title?: string; terms?: Record<string, unknown>; amount?: number; durationDays?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const kind = body.kind?.trim() ?? '';
      const counterpartyId = body.counterpartyId?.trim() ?? '';
      const title = body.title?.trim() ?? '';
      const amount = Math.round(Number(body.amount ?? 0) * 100) / 100;
      const durationDays = Number(body.durationDays ?? 30);
      if (!['employment', 'intellectual_service', 'capacity', 'strategic'].includes(kind)) return Response.json({ ok: false, error: 'Unsupported contract kind' }, { status: 400 });
      const counterparty = await withRepository(env, (repository) => repository.query("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [counterpartyId]));
      if (!counterpartyId || counterpartyId === viewer.id || !counterparty?.rows[0]) return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
      if (title.length < 3 || title.length > 140 || !Number.isFinite(amount) || amount < 0 || amount > 100000 || !Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) return Response.json({ ok: false, error: 'Contract terms are outside engine bounds' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createContractPostgres(repository, { proposerId: viewer.id, kind, counterpartyId, title, terms: body.terms ?? {}, amount, durationDays, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract creation failed' }, { status: 409 });
      }
    }

    if (url.pathname === '/api/contracts/supply' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => listSupplyContracts(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }

    if (url.pathname === '/api/contracts/supply/propose' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{
        counterpartyId?: string;
        proposerRole?: 'buyer' | 'seller';
        resourceType?: 'food' | 'energy' | 'material' | 'compute';
        dailyQuantity?: number;
        unitPrice?: number;
        totalDays?: number;
        penaltyPerDefault?: number;
        title?: string;
        correlationId?: string;
      }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const counterpartyId = body.counterpartyId?.trim() ?? '';
      const proposerRole = body.proposerRole === 'seller' ? 'seller' : 'buyer';
      const resourceType = body.resourceType ?? 'energy';
      const dailyQuantity = Number(body.dailyQuantity ?? 0);
      const unitPrice = Number(body.unitPrice ?? 0);
      const totalDays = Number(body.totalDays ?? 30);
      const penaltyPerDefault = Number(body.penaltyPerDefault ?? 0);
      const title = body.title?.trim();

      if (!counterpartyId || counterpartyId === viewer.id) {
        return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
      }
      if (!['food', 'energy', 'material', 'compute'].includes(resourceType)) {
        return Response.json({ ok: false, error: 'Invalid commodity resource type' }, { status: 400 });
      }
      if (dailyQuantity <= 0 || unitPrice <= 0 || totalDays < 1 || totalDays > 365) {
        return Response.json({ ok: false, error: 'Quantity, price, and duration are outside engine bounds' }, { status: 400 });
      }

      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key is required' }, { status: 400 });

      try {
        const result = await withRepository(env, (repository) =>
          proposeSupplyContract(repository, {
            proposerId: viewer.id,
            counterpartyId,
            proposerRole,
            resourceType,
            dailyQuantity,
            unitPrice,
            totalDays,
            penaltyPerDefault,
            title,
            correlationId,
          }),
        );
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Supply contract proposal failed' }, { status: 409 });
      }
    }

    const contractTicksMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/ticks$/);
    if (contractTicksMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => getContractDeliveryTicks(repository, contractTicksMatch[1], viewer.id));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to fetch delivery ticks';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /denied/i.test(message) ? 403 : 409 });
      }
    }

    const contractActionMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(accept|cancel)$/);
    if (contractActionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = contractActionMatch[2] === 'cancel'
          ? await withRepository(env, async (repository) => {
              const isSupply = await repository.query('SELECT contract_id FROM supply_contracts WHERE contract_id = $1', [contractActionMatch[1]]);
              if (isSupply.rows[0]) return cancelSupplyContract(repository, contractActionMatch[1], viewer.id);
              return cancelContractPostgres(repository, contractActionMatch[1], viewer.id);
            })
          : await withRepository(env, async (repository) => {
              const isSupply = await repository.query('SELECT contract_id FROM supply_contracts WHERE contract_id = $1', [contractActionMatch[1]]);
              if (isSupply.rows[0]) return acceptSupplyContract(repository, contractActionMatch[1], viewer.id);
              return acceptContractPostgres(repository, contractActionMatch[1], viewer.id);
            });
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Contract action failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /only .* may/i.test(message) ? 403 : 409 });
      }
    }
    const contractDisputeMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(dispute|resolve)$/);
    if (contractDisputeMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        if (contractDisputeMatch[2] === 'dispute') {
          const parsed = await parseJsonBody<{ reason?: string }>(request);
          if (!parsed.ok) return parsed.response;
          const body = parsed.value;
          const reason = body.reason?.trim() ?? '';
          if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
          const result = await withRepository(env, (repository) => openDisputePostgres(repository, { contractId: contractDisputeMatch[1], claimantId: viewer.id, reason }));
          if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
          return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyOpen ? 200 : 201 });
        }
        const parsed = await parseJsonBody<{ outcome?: string; resolution?: string }>(request);
        if (!parsed.ok) return parsed.response;
        const body = parsed.value;
        if (!['uphold', 'void'].includes(body.outcome ?? '') || (body.resolution?.trim().length ?? 0) < 10) return Response.json({ ok: false, error: 'A bounded arbitration outcome and resolution are required' }, { status: 400 });
        const result = await withRepository(env, (repository) => resolveContractDisputePostgres(repository, { contractId: contractDisputeMatch[1], resolverId: viewer.id, outcome: body.outcome as 'uphold' | 'void', resolution: body.resolution!.trim().slice(0, 1000) }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Contract dispute operation failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /authority|required|only/i.test(message) ? 403 : 409 });
      }
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

    if (url.pathname === '/api/dynasty' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      const email = viewer?.email || 'amara@earth.local';
      const humanId = viewer?.id || 'H-0044';
      const humanName = viewer?.name || 'Amara Vance';
      const result = await withRepository(env, (repository) => getDynastyOverview(repository, email, humanId, humanName));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }

    if (url.pathname === '/api/dynasty/perks/unlock' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ perkKey?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const perkKey = parsed.value.perkKey?.trim() ?? '';
      if (!perkKey) return Response.json({ ok: false, error: 'Perk key is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => unlockDynastyPerk(repository, viewer.email || 'amara@earth.local', perkKey, 1, resolveIdempotencyKey(request, parsed.value.correlationId)));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Perk unlock failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }

    if (url.pathname === '/api/dynasty/heirlooms/equip' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ heirloomId?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const heirloomId = parsed.value.heirloomId?.trim() ?? '';
      if (!heirloomId) return Response.json({ ok: false, error: 'Heirloom ID is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => equipDynastyHeirloom(repository, viewer.email || 'amara@earth.local', heirloomId, viewer.id, resolveIdempotencyKey(request, parsed.value.correlationId)));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Equip failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }

    if (url.pathname === '/api/dynasty/heirlooms/forge' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; heirloomType?: string; inscription?: string; statBuff?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const name = parsed.value.name?.trim() ?? '';
      const heirloomType = parsed.value.heirloomType?.trim() ?? 'dynasty_standard';
      const inscription = parsed.value.inscription?.trim() ?? 'Forged by the house patriarch.';
      const statBuff = parsed.value.statBuff?.trim() ?? '+5% Prestige & Influence';
      if (!name) return Response.json({ ok: false, error: 'Heirloom name is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => forgeDynastyHeirloom(repository, viewer.email || 'amara@earth.local', name, heirloomType, inscription, statBuff, resolveIdempotencyKey(request, parsed.value.correlationId)));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Heirloom forge failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }

    if (url.pathname === '/api/dynasty/motto' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ motto?: string; dynastyName?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const motto = parsed.value.motto?.trim() ?? '';
      const dynastyName = parsed.value.dynastyName?.trim();
      try {
        const result = await withRepository(env, (repository) => updateDynastyMotto(repository, viewer.email || 'amara@earth.local', motto, dynastyName, resolveIdempotencyKey(request, parsed.value.correlationId)));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Motto update failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }

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
      const parsed = await parseJsonBody<{ commodity?: string; size?: number; strikePrice?: number; expiryGameDay?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const commodity = parsed.value.commodity?.toLowerCase().trim() ?? 'energy';
      const size = Number(parsed.value.size);
      const strikePrice = Number(parsed.value.strikePrice);
      const expiryGameDay = Number(parsed.value.expiryGameDay);
      const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);

      try {
        const result = await withRepository(env, (repository) => createFuturesListing(repository, {
          sellerId: viewer.id,
          commodity,
          size,
          strikePrice,
          expiryGameDay,
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
      const durationHours = Number(body.durationHours ?? 72);
      if (!title || title.length < 8 || title.length > 140) return Response.json({ ok: false, error: 'Proposal title must be 8–140 characters' }, { status: 400 });
      if (!proposalBody || proposalBody.length < 20 || proposalBody.length > 4000) return Response.json({ ok: false, error: 'Proposal body must be 20–4000 characters' }, { status: 400 });
      if (!Number.isInteger(durationHours) || durationHours < 24 || durationHours > 168) return Response.json({ ok: false, error: 'Decision window must be between 24 and 168 hours' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      const targetCategory = body.target?.category?.trim() || null;
      if (targetCategory && !['market', 'finance', 'services', 'technology'].includes(targetCategory)) return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createProposalPostgres(repository, { humanId: human.id, institutionId, title, body: proposalBody, durationHours, ruleVersionId: body.ruleVersionId, targetCategory, targetValue: body.target?.value ?? null, correlationId }));
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
    const proposeMergerMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/merger\/propose$/);
    if (proposeMergerMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ targetBusinessId?: string; pricePerShare?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const targetBusinessId = body.targetBusinessId?.trim();
      const pricePerShare = Number(body.pricePerShare);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!targetBusinessId || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || !correlationId) {
        return Response.json({ ok: false, error: 'Target business ID, positive price per share, and correlation ID are required' }, { status: 400 });
      }
      try {
        const result = await withRepository(env, (repository) => proposeMergerPostgres(repository, { acquirerId: viewer.id, acquirerBusinessId: proposeMergerMatch[1], targetBusinessId, pricePerShare, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Merger proposal failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    const executeMergerMatch = url.pathname.match(/^\/api\/businesses\/merger\/([^/]+)\/execute$/);
    if (executeMergerMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => executeMergerPostgres(repository, { callerId: viewer.id, mergerId: executeMergerMatch[1], correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Merger execution failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    if (url.pathname === '/api/businesses' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; sector?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const name = body.name?.trim();
      const sector = body.sector?.trim() ?? 'maintenance';
      const sectors = ['energy', 'extraction', 'components', 'machines', 'maintenance', 'housing', 'compute', 'r-and-d', 'it-services', 'consulting', 'logistics', 'healthcare', 'education'];
      if (!name || name.length < 3 || name.length > 80 || !sectors.includes(sector)) return Response.json({ ok: false, error: 'Business name or sector is invalid' }, { status: 400 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createBusinessPostgres(repository, { ownerId: viewer.id, name, sector, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Business registration failed';
        return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /requires/i.test(message) ? 409 : 400 });
      }
    }
    const employeeCollectionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/employees$/);
    if (employeeCollectionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; role?: string; wage?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      const wage = Number(body.wage);
      if (!correlationId || !body.name?.trim() || !body.role?.trim() || !Number.isFinite(wage) || wage <= 0) return Response.json({ ok: false, error: 'Employee name, role, wage, and correlation ID are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => hireEmployeePostgres(repository, { humanId: viewer.id, businessId: employeeCollectionMatch[1], name: body.name!, role: body.role!, wage, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Employee hiring failed' }, { status: 409 });
      }
    }
    const employeeActionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/employees\/([^/]+)\/(train|dismiss)$/);
    if (employeeActionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
      try {
        const input = { humanId: viewer.id, businessId: employeeActionMatch[1], employeeId: employeeActionMatch[2], correlationId };
        const result = await withRepository(env, (repository) => employeeActionMatch[3] === 'train' ? trainEmployeePostgres(repository, input) : dismissEmployeePostgres(repository, input));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Employee action failed' }, { status: 409 });
      }
    }
    const businessLiquidationMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/liquidate$/);
    if (businessLiquidationMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ otp?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'A valid decommission correlationId is required' }, { status: 400 });
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for business liquidation' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => liquidateBusinessPostgres(repository, { ownerId: viewer.id, businessId: businessLiquidationMatch[1], correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Business liquidation failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /owner|distressed|insolvent/i.test(message) ? 409 : 400 });
      }
    }
    const businessDividendsMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/dividends$/);
    if (businessDividendsMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const amount = Number(body.amount);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(amount) || amount <= 0 || !correlationId) return Response.json({ ok: false, error: 'A valid positive amount and correlation ID are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => distributeDividendsPostgres(repository, { callerId: viewer.id, businessId: businessDividendsMatch[1], totalAmount: amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Dividend distribution failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient|owner|manager/i.test(message) ? 409 : 400 });
      }
    }
    const businessProfileMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)$/);
    if (businessProfileMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => readBusinessProfilePostgres(repository, businessProfileMatch[1], viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      if (result.error) return Response.json({ ok: false, error: result.error }, { status: 403 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if ((url.pathname === '/api/businesses/kline-works/policy' || url.pathname === '/api/businesses/me/policy') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ policy?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!['reliability', 'margin', 'capacity'].includes(body.policy ?? '')) return Response.json({ ok: false, error: 'Unknown business policy' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => setBusinessPolicyPostgres(repository, { humanId: viewer.id, policy: body.policy! }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business policy update failed' }, { status: 404 });
      }
    }
    const managerMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/manager$/);
    if (managerMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ managerId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      try {
        const result = await withRepository(env, (repository) => appointManagerPostgres(repository, { ownerId: viewer.id, businessId: managerMatch[1], managerId: body.managerId?.trim() ?? '' }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Manager appointment failed' }, { status: 403 });
      }
    }
    const ownershipRegistryMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/ownership$/);
    if (ownershipRegistryMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => ownershipRegistryPostgres(repository, ownershipRegistryMatch[1]));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business not found' }, { status: 404 });
      }
    }
    const financialsMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/financials$/);
    if (financialsMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => readBusinessPostgres(repository, financialsMatch[1], viewer.id));
      if (result?.business) return Response.json({ ...result, accounting: { revenue: 'market-cleared sales and accepted contract income', operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax', profit: 'revenue minus operating costs' }, persistence: 'planetscale-postgres' });
      return Response.json({ ok: false, error: result?.error ?? 'Business financial statement is not available to this Human' }, { status: 403 });
    }
    const constitutionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/constitution$/);
    if (constitutionMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => repository.query('SELECT business_constitutions.*, businesses.name, businesses.owner_id FROM business_constitutions JOIN businesses ON businesses.id = business_constitutions.business_id WHERE business_constitutions.business_id = $1', [constitutionMatch[1]]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      if (!result.rows[0]) return Response.json({ ok: false, error: 'Business constitution not found' }, { status: 404 });
      return Response.json({ constitution: result.rows[0], management: { ownerId: result.rows[0].owner_id, ownershipAndManagementAreSeparate: true }, persistence: 'planetscale-postgres' });
    }
    if (constitutionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const shareholderVoteThreshold = Number(body.shareholderVoteThreshold ?? 0.5);
      const boardApprovalThreshold = Number(body.boardApprovalThreshold ?? 0.5);
      const dilutionNoticeDays = Number(body.dilutionNoticeDays ?? 3);
      if (![shareholderVoteThreshold, boardApprovalThreshold].every((value) => Number.isFinite(value) && value >= 0.5 && value <= 1) || !Number.isInteger(dilutionNoticeDays) || dilutionNoticeDays < 1 || dilutionNoticeDays > 30) return Response.json({ ok: false, error: 'Constitution thresholds are invalid' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => updateConstitutionPostgres(repository, { ownerId: viewer.id, businessId: constitutionMatch[1], shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business constitution update failed' }, { status: 403 });
      }
    }
    const shareTransferMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/transfer$/);
    if (shareTransferMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ businessId?: string; recipientId?: string; shares?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const recipientId = body.recipientId?.trim() ?? '';
      const shares = Number(body.shares);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !correlationId) return Response.json({ ok: false, error: 'Invalid share transfer terms' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => transferSharesPostgres(repository, { holderId: viewer.id, businessId: body.businessId?.trim() || null, recipientId, shares, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Share transfer failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    const shareIssueMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/issue$/);
    if (shareIssueMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ recipientId?: string; shares?: number; pricePerShare?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const recipientId = body.recipientId?.trim() ?? '';
      const shares = Number(body.shares);
      const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000 || !correlationId) return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => issueSharesPostgres(repository, { ownerId: viewer.id, businessId: shareIssueMatch[1], recipientId, shares, pricePerShare, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share issuance failed' }, { status: 409 });
      }
    }
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'GET') {
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
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'POST') {
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ name?: string; estatePeriodDays?: number; successorHumanId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const successorName = body.name?.trim();
      const estatePeriodDays = Number(body.estatePeriodDays ?? 30);
      if (!successorName || successorName.length < 2) return Response.json({ ok: false, error: 'Successor name is required' }, { status: 400 });
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
    const maintenanceMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/maintenance$/);
    if (maintenanceMatch && request.method === 'POST') {
      const machineId = maintenanceMatch[1];
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const amount = Number(body.amount ?? 10);
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Maintenance amount must be positive' }, { status: 400 });
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => maintainMachinePostgres(repository, { machineId, ownerId: viewer.id, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Machine maintenance failed';
        return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
      }
    }
    const decommissionMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/decommission$/);
    if (decommissionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ otp?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for decommissioning an asset' }, { status: 401 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => recycleMachinePostgres(repository, { machineId: decommissionMatch[1], ownerId: viewer.id, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Machine recycling failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    const utilizationMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/utilization$/);
    if (utilizationMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ utilization?: number }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const utilization = Number(body.utilization);
      if (!Number.isInteger(utilization) || utilization < 0 || utilization > 100) return Response.json({ ok: false, error: 'Utilization must be a whole percentage from 0 to 100' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => setMachineUtilizationPostgres(repository, { machineId: utilizationMatch[1], ownerId: viewer.id, utilization }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Machine utilization update failed' }, { status: 404 });
      }
    }
    const upgradeMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/upgrade$/);
    if (upgradeMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ otp?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine upgrades' }, { status: 401 });
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => upgradeMachinePostgres(repository, { machineId: upgradeMatch[1], ownerId: viewer.id, correlationId, creditCost: 600, componentsCost: 20 }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Machine upgrade failed';
        return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
      }
    }
    const saleMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/sell$/);
    if (saleMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ buyerId?: string; price?: number; otp?: string; correlationId?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const buyerId = body.buyerId?.trim();
      const price = Math.round(Number(body.price) * 100) / 100;
      const correlationId = resolveIdempotencyKey(request, body.correlationId);
      if (!buyerId || buyerId === viewer.id || !Number.isFinite(price) || price <= 0 || price > 1000000) return Response.json({ ok: false, error: 'Buyer and sale price are invalid' }, { status: 400 });
      if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine sale' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => sellMachinePostgres(repository, { machineId: saleMatch[1], sellerId: viewer.id, buyerId, price, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Machine sale failed';
        return Response.json({ ok: false, error: message }, { status: message.includes('not found') ? 404 : 409 });
      }
    }
    return Response.json({ service: 'earth-world', environment: env.ENVIRONMENT, status: 'edge-ready' });
  },
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    const result = await withRepository(env, async (repository) => {
      await resolveProposalsPostgres(repository);
      const world = await advanceWorldPostgres(repository, 5, String(_event.scheduledTime));
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
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key, X-Request-ID, X-Requested-With, X-Earth-API-Version, Accept',
          'Access-Control-Expose-Headers': 'X-Request-ID, X-EARTH-API-Version',
          'Access-Control-Allow-Credentials': 'true',
          'Access-Control-Max-Age': '86400',
          'Vary': 'Origin',
          'X-Request-ID': requestId,
        },
      });
    }
    const url = new URL(request.url);
    const isDataRequest = url.pathname.startsWith('/api/') || url.pathname.startsWith('/edge/') || url.pathname === '/health' || url.pathname === '/ready' || url.pathname === '/api/ready';
    let response: Response;
    try {
      if (isDataRequest) authorityMode(env);
      if (isDataRequest) {
        response = await worker.fetch(request, env, ctx);
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
    headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, Idempotency-Key, X-Request-ID, X-Requested-With, X-Earth-API-Version, Accept');
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
