import { DurableObject } from 'cloudflare:workers';
import { probePostgres } from './postgres';
import { authorityMode, withPostgresRepository, withRepository } from './repository';
import { cancelMarketOrder as cancelMarketOrderPostgres, listMarketOrders as listMarketOrdersPostgres, settleMarket as settleMarketPostgres, submitMarketOrder as submitMarketOrderPostgres } from './market-postgres';
import { declarePersonalInsolvency as declarePersonalInsolvencyPostgres, publicSpending as publicSpendingPostgres, recoverInstitution as recoverInstitutionPostgres, settleTax as settleTaxPostgres } from './finance-postgres';
import { getLifeStatus as getLifeStatusPostgres, getSuccessor as getSuccessorPostgres, liquidateExpiredEstates as liquidateExpiredEstatesPostgres, registerSuccessor as registerSuccessorPostgres, settleInheritance as settleInheritancePostgres } from './lifecycle-postgres';
import { acceptContract as acceptContractPostgres, cancelContract as cancelContractPostgres, createContract as createContractPostgres, openDispute as openDisputePostgres } from './contracts-postgres';
import { resolveContractDispute as resolveContractDisputePostgres } from './arbitration-postgres';
import { appointManager as appointManagerPostgres, createBusiness as createBusinessPostgres, issueShares as issueSharesPostgres, ownershipRegistry as ownershipRegistryPostgres, setPolicy as setBusinessPolicyPostgres, transferShares as transferSharesPostgres, updateConstitution as updateConstitutionPostgres } from './business-postgres';
import { acquireMachine as acquireMachinePostgres, maintainMachine as maintainMachinePostgres, sellMachine as sellMachinePostgres, setMachineUtilization as setMachineUtilizationPostgres, upgradeMachine as upgradeMachinePostgres } from './machines-postgres';
import { recycleMachine as recycleMachinePostgres } from './machines-recycling-postgres';
import { createResearchProject as createResearchProjectPostgres, fundResearchProject as fundResearchProjectPostgres, grantPatent as grantPatentPostgres, licenseTechnology as licenseTechnologyPostgres } from './technology-postgres';
import { castVote as castVotePostgres, createProposal as createProposalPostgres, executeProposal as executeProposalPostgres, resolveProposals as resolveProposalsPostgres } from './governance-postgres';
import { advanceWorld as advanceWorldPostgres } from './scheduler-postgres';
import { loginIdentity as loginIdentityPostgres, registerIdentity as registerIdentityPostgres } from './auth-postgres';
import { worldSnapshot as worldSnapshotPostgres } from './world-postgres';
import { listAssistants as listAssistantsPostgres, updateAssistantPolicy as updateAssistantPolicyPostgres, upgradeAssistant as upgradeAssistantPostgres } from './ai-postgres';
import { changeDelegation as changeDelegationPostgres, changeRole as changeRolePostgres, listRoles as listRolesPostgres } from './roles-postgres';
import { changeCommunityMembership as changeCommunityMembershipPostgres, contributeToCommunity as contributeToCommunityPostgres, createCommunity as createCommunityPostgres, listCommunities as listCommunitiesPostgres, listCommunityContributions as listCommunityContributionsPostgres, listCommunityMembers as listCommunityMembersPostgres } from './communities-postgres';
import { deliverOutbox } from './outbox-postgres';
import { changeCityResidency as changeCityResidencyPostgres, changeCorporationMembership as changeCorporationMembershipPostgres, cityQualification as cityQualificationPostgres, corporationQualification as corporationQualificationPostgres, contributeToCorporation as contributeToCorporationPostgres, createCity as createCityPostgres, createCorporation as createCorporationPostgres, listCities as listCitiesPostgres, listCorporations as listCorporationsPostgres, setCityBudget as setCityBudgetPostgres, spendCorporationTreasury as spendCorporationTreasuryPostgres } from './institutions-postgres';
import { auditWorld as auditWorldPostgres, getServiceStatus as getServiceStatusPostgres, listAuthorityEvents as listAuthorityEventsPostgres, listEvents as listEventsPostgres, listGovernanceProposals as listGovernanceProposalsPostgres, listGovernanceRules as listGovernanceRulesPostgres, listHistory as listHistoryPostgres, listInstitutions as listInstitutionsPostgres, listMembershipEvents as listMembershipEventsPostgres, listNotifications as listNotificationsPostgres, listProductionEvents as listProductionEventsPostgres, listOwnershipEvents as listOwnershipEventsPostgres, listRankings as listRankingsPostgres, listTechnology as listTechnologyPostgres, markNotificationRead as markNotificationReadPostgres, readBusiness as readBusinessPostgres, readBusinessProfile as readBusinessProfilePostgres } from './read-postgres';
import { parseJsonBody } from './request-validation';

const SESSION_DAYS = 7;
const WEB_ASSET_VERSION = '2026-08-15-auth-recovery-1';
const MACHINE_CATALOG: Record<string, { output: string; credit: number; material: number; capacity: number }> = {
  extractor: { output: 'material', credit: 4200, material: 80, capacity: 2 },
  'energy-array': { output: 'energy', credit: 3600, material: 60, capacity: 2 },
  'compute-node': { output: 'compute', credit: 5200, material: 100, capacity: 1.5 },
  fabricator: { output: 'components', credit: 4800, material: 90, capacity: 1.8 },
  'housing-fabricator': { output: 'components', credit: 5000, material: 110, capacity: 1.6 },
  'research-cluster': { output: 'compute', credit: 7000, material: 140, capacity: 1.2 },
};
const encoder = new TextEncoder();
const bytesToBase64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const base64ToBytes = (value: string) => Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const bytesToBase32 = (bytes: Uint8Array) => {
  let output = ''; let buffer = 0; let bits = 0;
  for (const byte of bytes) { buffer = (buffer << 8) | byte; bits += 8; while (bits >= 5) { output += base32Alphabet[(buffer >>> (bits - 5)) & 31]; bits -= 5; } }
  if (bits > 0) output += base32Alphabet[(buffer << (5 - bits)) & 31];
  return output;
};
const base32ToBytes = (value: string) => {
  let buffer = 0; let bits = 0; const output: number[] = [];
  for (const char of value.replace(/=+$/, '').toUpperCase()) { const index = base32Alphabet.indexOf(char); if (index < 0) continue; buffer = (buffer << 5) | index; bits += 5; if (bits >= 8) { output.push((buffer >>> (bits - 8)) & 255); bits -= 8; } }
  return new Uint8Array(output);
};
async function totp(secret: string, timestamp = Date.now()): Promise<string> {
  const counter = Math.floor(timestamp / 30000); const data = new ArrayBuffer(8); const view = new DataView(data); view.setUint32(4, counter);
  const key = await crypto.subtle.importKey('raw', base32ToBytes(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const hash = new Uint8Array(await crypto.subtle.sign('HMAC', key, data)); const offset = hash[hash.length - 1] & 15;
  const value = ((hash[offset] & 127) << 24) | (hash[offset + 1] << 16) | (hash[offset + 2] << 8) | hash[offset + 3];
  return String(value % 1000000).padStart(6, '0');
}
async function validTotp(secret: string, code: string): Promise<boolean> {
  if (!/^\d{6}$/.test(code)) return false;
  for (const drift of [-30000, 0, 30000]) if (code === await totp(secret, Date.now() + drift)) return true;
  return false;
}
async function derivePassword(password: string, salt: Uint8Array, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, key, 256);
  return bytesToBase64(new Uint8Array(bits));
}
async function digest(value: string): Promise<string> {
  return bytesToBase64(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))));
}
function cookieValue(request: Request, name: string): string | null {
  const cookies = request.headers.get('Cookie')?.split(';').map((part) => part.trim()) ?? [];
  const value = cookies.find((part) => part.startsWith(`${name}=`));
  return value ? decodeURIComponent(value.slice(name.length + 1)) : null;
}
async function currentHuman(request: Request, env: Env, allowEstate = false): Promise<{ id: string; display_name: string; email: string; life_status: string } | null> {
  const token = cookieValue(request, 'earth_session');
  if (!token) return null;
  const tokenHash = await digest(token);
  const result = await withRepository(env, (repository) => repository.query<{ id: string; display_name: string; life_status: string; email: string }>("SELECT humans.id, humans.display_name, humans.life_status, auth_credentials.email FROM auth_sessions JOIN humans ON humans.id = auth_sessions.human_id JOIN auth_credentials ON auth_credentials.human_id = humans.id WHERE auth_sessions.token_hash = $1 AND auth_sessions.revoked_at IS NULL AND auth_sessions.expires_at > CURRENT_TIMESTAMP AND (humans.life_status = 'active' OR ($2 = 1 AND humans.life_status = 'estate'))", [tokenHash, allowEstate ? 1 : 0]));
  return result?.rows[0] ?? null;
}
async function sensitiveActionAllowed(env: Env, humanId: string, otp?: string): Promise<boolean> {
  const result = await withRepository(env, (repository) => repository.query<{ mfa_enabled: boolean; mfa_secret: string | null }>('SELECT mfa_enabled, mfa_secret FROM auth_credentials WHERE human_id = $1', [humanId]));
  const credential = result?.rows[0];
  return !credential?.mfa_enabled || Boolean(credential.mfa_secret && await validTotp(credential.mfa_secret, otp ?? ''));
}
function sessionCookie(token: string, maxAge: number): string {
  return `earth_session=${encodeURIComponent(token)}; Max-Age=${maxAge}; Path=/; HttpOnly; Secure; SameSite=Lax`;
}
async function issueActionToken(env: Env, humanId: string, action: 'verify_email' | 'reset_password', email: string): Promise<void> {
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await digest(token);
  const id = crypto.randomUUID();
  const expires = new Date(Date.now() + (action === 'verify_email' ? 24 : 1) * 3600000).toISOString();
  const result = await withRepository(env, (repository) => repository.query('INSERT INTO auth_action_tokens (id, human_id, token_hash, action, expires_at) VALUES ($1,$2,$3,$4,$5)', [id, humanId, tokenHash, action, expires]));
  if (!result) throw new Error('PostgreSQL authentication repository is unavailable');
  if (!env.EMAIL || !env.EMAIL_FROM) {
    throw new Error('Transactional email is not configured');
  }
  const path = action === 'verify_email'
    ? `/app?verify_token=${encodeURIComponent(token)}`
    : `/app?reset_token=${encodeURIComponent(token)}`;
  const subject = action === 'verify_email' ? 'Verify your EARTH identity' : 'Reset your EARTH password';
  const text = `${subject}\n\nOpen this link to continue: https://earthuc.com${path}\n\nThis link expires soon and can only be used once.`;
  try {
    const delivery = await env.EMAIL.send({ to: email, from: { email: env.EMAIL_FROM, name: 'EARTH Identity' }, replyTo: env.EMAIL_REPLY_TO, subject, text, html: `<p>${subject}</p><p><a href="https://earthuc.com${path}">Continue securely</a></p><p>This link expires soon and can only be used once.</p>` });
    console.info(JSON.stringify({ event: 'transactional_email_accepted', action, messageId: delivery?.messageId ?? null }));
  } catch (error) {
    const details = error && typeof error === 'object' ? error as { code?: unknown; message?: unknown } : {};
    console.error(JSON.stringify({ event: 'transactional_email_failed', action, code: String(details.code ?? 'unknown'), message: String(details.message ?? 'unknown') }));
    // Do not let a failed delivery consume the resend throttle window.
    await withRepository(env, (repository) => repository.query('DELETE FROM auth_action_tokens WHERE id = $1', [id]));
    throw error;
  }
}

export class MarketCoordinator extends DurableObject<Env> {
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
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
      return new Response('WebSocket upgrade required', { status: 426 });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    server.send(JSON.stringify({ type: 'ready', channel: 'earth-world', coordinator: 'market' }));
    return new Response(null, { status: 101, webSocket: client });
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
      const authority = await repository.query("SELECT 1 FROM role_assignments WHERE role_id = 'ROLE-OUC-DELEGATE' AND human_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') UNION ALL SELECT 1 FROM authority_delegations WHERE role_id = 'ROLE-OUC-DELEGATE' AND delegate_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [viewer.id]);
      if (!authority.rows[0]) throw new Error('Only an active OUC Delegate may advance the simulation clock manually');
      await resolveProposalsPostgres(repository);
      return advanceWorldPostgres(repository, 1440);
    });
    if (!result) throw new Error('PostgreSQL repository is unavailable');
    const state = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewer.id));
    return Response.json({ ok: true, result, state, persistence: 'planetscale-postgres' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to advance the simulation clock';
    return Response.json({ ok: false, error: message }, { status: /delegate/i.test(message) ? 403 : 409 });
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
  const result = await withRepository(env, (repository) => listRankingsPostgres(repository));
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
    if (url.pathname === '/api/auth/me' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      return Response.json({ authenticated: Boolean(human), human, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/auth/mfa/enroll' && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const secret = bytesToBase32(crypto.getRandomValues(new Uint8Array(20)));
      const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_secret = $1, mfa_enabled = false WHERE human_id = $2', [secret, human.id]));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ ok: true, secret, otpauth: `otpauth://totp/EARTH:${encodeURIComponent(human.email)}?secret=${secret}&issuer=EARTH`, message: 'Scan or enter this secret in an authenticator, then confirm with a six-digit code.' });
    }
    if (url.pathname === '/api/auth/mfa/confirm' && request.method === 'POST') {
      const human = await currentHuman(request, env); if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ code?: string }>();
      const credential = (await withRepository(env, (repository) => repository.query<{ mfa_secret: string | null }>('SELECT mfa_secret FROM auth_credentials WHERE human_id = $1', [human.id])))?.rows[0];
      if (!credential?.mfa_secret || !(await validTotp(credential.mfa_secret, body.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
      const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_enabled = true WHERE human_id = $1', [human.id]));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ ok: true, enabled: true });
    }
    if (url.pathname === '/api/auth/mfa/disable' && request.method === 'POST') {
      const human = await currentHuman(request, env); if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ code?: string }>();
      const credential = (await withRepository(env, (repository) => repository.query<{ mfa_secret: string | null; mfa_enabled: boolean }>('SELECT mfa_secret, mfa_enabled FROM auth_credentials WHERE human_id = $1', [human.id])))?.rows[0];
      if (!credential?.mfa_enabled || !credential.mfa_secret || !(await validTotp(credential.mfa_secret, body.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
      const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_enabled = false, mfa_secret = NULL WHERE human_id = $1', [human.id]));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ ok: true, enabled: false });
    }
    if (url.pathname === '/api/auth/sessions' && request.method === 'GET') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const token = cookieValue(request, 'earth_session');
      const currentHash = token ? await digest(token) : '';
      const sessions = await withRepository(env, (repository) => repository.query('SELECT id, created_at, expires_at, revoked_at, token_hash FROM auth_sessions WHERE human_id = $1 ORDER BY created_at DESC', [human.id]));
      if (!sessions) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ sessions: sessions.rows.map(({ token_hash: _tokenHash, ...session }) => ({ ...session, current: _tokenHash === currentHash })), persistence: 'planetscale-postgres' });
    }
    const revokeSessionMatch = url.pathname.match(/^\/api\/auth\/sessions\/([^/]+)$/);
    if (revokeSessionMatch && request.method === 'DELETE') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND human_id = $2 AND revoked_at IS NULL', [revokeSessionMatch[1], human.id]));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ ok: result.rowCount === 1, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/auth/sessions' && request.method === 'DELETE') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [human.id]));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
    }
    if (url.pathname === '/api/auth/register' && request.method === 'POST') {
      const parsed = await parseJsonBody<{ email?: string; password?: string; passwordConfirmation?: string; displayName?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const email = body.email?.trim().toLowerCase();
      const displayName = body.displayName?.trim();
      const password = body.password ?? '';
      if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return Response.json({ ok: false, error: 'A valid email is required' }, { status: 400 });
      if (!displayName || displayName.length < 2 || displayName.length > 80) return Response.json({ ok: false, error: 'Display name must be 2–80 characters' }, { status: 400 });
      if (password.length < 12) return Response.json({ ok: false, error: 'Password must be at least 12 characters' }, { status: 400 });
      if (password !== (body.passwordConfirmation ?? '')) return Response.json({ ok: false, error: 'Passwords do not match' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => registerIdentityPostgres(repository, { email, displayName, password }));
        if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
        try {
          const identity = result.human as { id: string; email: string };
          await issueActionToken(env, identity.id, 'verify_email', identity.email);
        } catch {
          return Response.json({ ok: false, error: 'Identity created, but the verification email could not be sent. Please retry shortly.' }, { status: 503 });
        }
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Identity creation failed';
        return Response.json({ ok: false, error: message }, { status: /already registered/i.test(message) ? 409 : 400 });
      }
    }
    if (url.pathname === '/api/auth/verify-email/resend' && request.method === 'POST') {
      const body = await request.json<{ email?: string }>();
      const email = body.email?.trim().toLowerCase();
      if (email) {
        const credential = (await withRepository(env, (repository) => repository.query<{ human_id: string; email: string; email_verified_at: string | null }>('SELECT human_id, email, email_verified_at FROM auth_credentials WHERE email = $1', [email])))?.rows[0];
        if (credential && !credential.email_verified_at) {
          const recentlySent = (await withRepository(env, (repository) => repository.query('SELECT 1 FROM auth_action_tokens WHERE human_id = $1 AND action = \'verify_email\' AND created_at > CURRENT_TIMESTAMP - INTERVAL \'60 seconds\' LIMIT 1', [credential.human_id])))?.rows[0];
          if (!recentlySent) {
            try {
              await issueActionToken(env, credential.human_id, 'verify_email', credential.email);
            } catch {
              return Response.json({ ok: false, error: 'The verification email could not be sent. Please try again shortly.' }, { status: 503 });
            }
          }
        }
      }
      return Response.json({ ok: true, message: 'If that identity exists and needs verification, a new email has been sent.' });
    }
    if (url.pathname === '/api/auth/verify-email' && request.method === 'GET') {
      const token = url.searchParams.get('token');
      if (!token) return Response.json({ ok: false, error: 'Verification token is required' }, { status: 400 });
      const tokenHash = await digest(token);
      const action = (await withRepository(env, (repository) => repository.query<{ id: string; human_id: string }>("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = $1 AND action = 'verify_email' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP", [tokenHash])))?.rows[0];
      if (!action) return Response.json({ ok: false, error: 'Verification link is invalid or expired' }, { status: 400 });
      const updated = await withRepository(env, (repository) => repository.transaction(async (tx) => {
        await tx.query('UPDATE auth_credentials SET email_verified_at = CURRENT_TIMESTAMP WHERE human_id = $1', [action.human_id]);
        await tx.query('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = $1', [action.id]);
        return true;
      }));
      if (!updated) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ ok: true, message: 'Email verified. You can now sign in.' });
    }
    if (url.pathname === '/api/auth/password-reset/request' && request.method === 'POST') {
      const body = await request.json<{ email?: string }>();
      const email = body.email?.trim().toLowerCase();
      const credential = email ? (await withRepository(env, (repository) => repository.query<{ human_id: string; email: string }>('SELECT human_id, email FROM auth_credentials WHERE email = $1', [email])))?.rows[0] : null;
      if (credential) {
        try { await issueActionToken(env, credential.human_id, 'reset_password', credential.email); } catch { /* Keep recovery responses generic. */ }
      }
      return Response.json({ ok: true, message: 'If that identity exists, recovery instructions have been sent.' });
    }
    if (url.pathname === '/api/auth/password-reset/complete' && request.method === 'POST') {
      const body = await request.json<{ token?: string; password?: string }>();
      if (!body.token || (body.password ?? '').length < 12) return Response.json({ ok: false, error: 'A valid token and 12-character password are required' }, { status: 400 });
      const tokenHash = await digest(body.token);
      const action = (await withRepository(env, (repository) => repository.query<{ id: string; human_id: string }>("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = $1 AND action = 'reset_password' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP", [tokenHash])))?.rows[0];
      if (!action) return Response.json({ ok: false, error: 'Recovery link is invalid or expired' }, { status: 400 });
      const salt = crypto.getRandomValues(new Uint8Array(16));
      const iterations = 100000;
      const passwordHash = await derivePassword(body.password, salt, iterations);
      const updated = await withRepository(env, (repository) => repository.transaction(async (tx) => {
        await tx.query('UPDATE auth_credentials SET password_hash = $1, password_salt = $2, password_iterations = $3 WHERE human_id = $4', [passwordHash, bytesToBase64(salt), iterations, action.human_id]);
        await tx.query('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = $1', [action.id]);
        await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [action.human_id]);
        return true;
      }));
      if (!updated) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return Response.json({ ok: true, message: 'Password reset. All previous sessions were revoked.' });
    }
    if (url.pathname === '/api/auth/login' && request.method === 'POST') {
      const parsed = await parseJsonBody<{ email?: string; password?: string; otp?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      const email = body.email?.trim().toLowerCase();
      if (!email || !body.password) return Response.json({ ok: false, error: 'Invalid email or password' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => loginIdentityPostgres(repository, { email, password: body.password ?? '', otp: body.otp ?? '', validTotp }));
        if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
        return new Response(JSON.stringify({ ok: result.ok, human: result.human, expiresAt: result.expiresAt }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie(String(result.token), Number(result.maxAge)) } });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Invalid email or password';
        const status = /too many/i.test(message) ? 429 : /verify|active/i.test(message) ? 403 : 401;
        return Response.json({ ok: false, error: message }, { status });
      }
    }
    if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
      const token = cookieValue(request, 'earth_session');
      if (token) await withRepository(env, async (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = $1', [await digest(token)]));
      return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
    }
    const publicMutation = url.pathname === '/api/auth/register' || url.pathname === '/api/auth/login' || url.pathname === '/api/auth/logout' || url.pathname === '/api/auth/verify-email/resend' || url.pathname === '/api/auth/password-reset/request' || url.pathname === '/api/auth/password-reset/complete';
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
        return Response.json(await stub.submitCommand({ humanId: human.id, command: await request.json() }));
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
      const body = await request.json<{ assistantId?: string; policy?: string; enabled?: boolean }>();
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
      const body = await request.json<{ assistantId?: string; otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for AI upgrade' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => upgradeAssistantPostgres(repository, { ownerId: viewer.id, assistantId: body.assistantId ?? '' }));
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'AI upgrade failed';
        return Response.json({ ok: false, error: message }, { status: /insufficient/i.test(message) ? 409 : 404 });
      }
    }
    if (url.pathname === '/api/services/status' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => getServiceStatusPostgres(repository, viewer.id));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/production/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 30)));
      const result = await withRepository(env, (repository) => listProductionEventsPostgres(repository, viewer.id, limit));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/health') {
      const postgres = await probePostgres(env.HYPERDRIVE);
      const postgresChecks = await withPostgresRepository(env, async (repository) => {
        const [core, feature, maintenance, reservations, governance, financial, assets, taxed, balances, machines, counts] = await Promise.all([
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['world_state','humans','market_prices','account_balances','ledger_entries','ownership_events','membership_events','authority_events']]),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['recycling_events','ai_assistants','machine_upgrade_events','machine_sales','production_events']]),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'maintenance_events' AND column_name = 'correlation_id'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'market_orders' AND column_name = 'reserved_credits'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['business_constitutions','business_management']]),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_financials'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_assets'"),
          repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'business_financials' AND column_name = 'taxed_revenue'"),
          repository.query('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
          repository.query('SELECT COUNT(*)::integer AS invalid FROM machines WHERE condition < 0 OR condition > 100'),
          Promise.all([repository.query('SELECT COUNT(*)::integer AS count FROM humans'), repository.query('SELECT COUNT(*)::integer AS count FROM businesses'), repository.query('SELECT COUNT(*)::integer AS count FROM ledger_entries'), repository.query("SELECT COUNT(*)::integer AS count FROM world_state WHERE id = 'WORLD'")]),
        ]);
        return { checks: { database: true, coreSchema: Number(core.rows[0]?.count ?? 0) === 8, featureSchema: Number(feature.rows[0]?.count ?? 0) === 5, maintenanceIdempotency: Number(maintenance.rows[0]?.count ?? 0) === 1, marketCreditReservations: Number(reservations.rows[0]?.count ?? 0) === 1, businessGovernanceSchema: Number(governance.rows[0]?.count ?? 0) === 2, businessFinancialSchema: Number(financial.rows[0]?.count ?? 0) === 1, businessAssetSchema: Number(assets.rows[0]?.count ?? 0) === 1, businessTaxSchema: Number(taxed.rows[0]?.count ?? 0) === 1, balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0, machineConditionsBounded: Number(machines.rows[0]?.invalid ?? 0) === 0 }, counts: { humans: Number(counts[0].rows[0]?.count ?? 0), businesses: Number(counts[1].rows[0]?.count ?? 0), ledger: Number(counts[2].rows[0]?.count ?? 0), world: Number(counts[3].rows[0]?.count ?? 0) } };
      });
      const checks = postgresChecks?.checks ?? { database: false, coreSchema: false, featureSchema: false, maintenanceIdempotency: false, marketCreditReservations: false, businessGovernanceSchema: false, businessFinancialSchema: false, businessAssetSchema: false, businessTaxSchema: false, balancesNonNegative: false, machineConditionsBounded: false };
      const shadow = postgresChecks?.counts ?? null;
      return Response.json({
        ok: Object.values(checks).every(Boolean),
        checks: { ...checks, postgresConfigured: postgres.configured, postgresReachable: postgres.reachable, postgresSchemaReady: postgres.schemaReady, postgresDataReady: postgres.dataReady, postgresShadowParity: Boolean(shadow && postgres.dataReady) },
        postgres: { serverVersion: postgres.serverVersion ?? null, featureTableCount: postgres.featureTableCount ?? 0, dataReady: postgres.dataReady },
        shadow: { postgres: shadow, parity: Boolean(shadow && postgres.dataReady) },
        persistence: 'planetscale-postgres',
        migration: { target: 'planetscale-postgres', stage: postgres.schemaReady && postgres.dataReady ? 'postgres-authority-active' : postgres.schemaReady ? 'schema-ready-awaiting-data-verification' : 'connectivity-probe' },
        authority: 'postgres',
        environment: env.ENVIRONMENT,
        workerVersion: '0.1.0',
      });
    }
    if (url.pathname === '/api/world/activity' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, async (repository) => {
        const [world, technology] = await Promise.all([
          repository.query('SELECT game_day, market_batch_seconds FROM world_state WHERE id = $1', ['WORLD']),
          repository.query('SELECT progress FROM technologies WHERE owner_id = $1 ORDER BY id LIMIT 1', [viewer.id]),
        ]);
        return { activity: [{ type: 'world_clock', day: world.rows[0]?.game_day ?? 184 }, { type: 'research_progress', progress: technology.rows[0]?.progress ?? 0 }, { type: 'market_cycle', batch: world.rows[0]?.market_batch_seconds ?? 498 }] };
      });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
      const result = await withRepository(env, (repository) => listEventsPostgres(repository, viewer.id, limit));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/notifications' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)));
      const result = await withRepository(env, (repository) => listNotificationsPostgres(repository, viewer.id, limit));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    const notificationReadMatch = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
    if (notificationReadMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => markNotificationReadPostgres(repository, viewer.id, notificationReadMatch[1]));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if ((url.pathname === '/api/audit' || url.pathname === '/api/world/audit') && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const result = await withRepository(env, (repository) => auditWorldPostgres(repository, viewer.id));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/institutions' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listInstitutionsPostgres(repository));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
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
      const body = await request.json<{ delegateHumanId?: string }>();
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
      const body = await request.json<{ name?: string; founderId?: string; correlationId?: string }>();
      const name = body.name?.trim();
      const founderId = viewer.id;
      if (!name || name.length < 3 || name.length > 80) return Response.json({ ok: false, error: 'Community name must be 3–80 characters' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
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
      const body = await request.json<{ humanId?: string }>();
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
      const body = await request.json<{ humanId?: string; amount?: number; correlationId?: string }>();
      const authenticatedHuman = await currentHuman(request, env);
      if (!authenticatedHuman) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const humanId = authenticatedHuman.id;
      const amount = Math.round(Number(body.amount) * 100) / 100;
      const correlationId = body.correlationId || crypto.randomUUID();
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
    if (url.pathname === '/api/rankings' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listRankingsPostgres(repository));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/history' && request.method === 'GET') {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 25)));
      const result = await withRepository(env, (repository) => listHistoryPostgres(repository, limit));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/ownership/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      const result = await withRepository(env, (repository) => listOwnershipEventsPostgres(repository, viewer.id, limit));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/membership/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      const result = await withRepository(env, (repository) => listMembershipEventsPostgres(repository, viewer.id, limit));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/governance/authority/events' && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
      const result = await withRepository(env, (repository) => listAuthorityEventsPostgres(repository, viewer.id, limit));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/cities' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listCitiesPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/cities' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; communityId?: string }>();
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
      const body = await request.json<{ name?: string; cityId?: string }>();
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
      const body = await request.json<{ category?: string; amount?: number; correlationId?: string }>();
      const category = body.category?.trim();
      const amount = Number(body.amount);
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!category || !Number.isFinite(amount) || amount < 0 || correlationId.length > 120) return Response.json({ ok: false, error: 'A valid budget category, amount, and correlation ID are required' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => setCityBudgetPostgres(repository, { humanId: viewer.id, cityId: cityBudgetMatch[1], category, amount, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'City budget update failed';
        return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
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
      const body = request.method === 'POST' ? await request.json<{ correlationId?: string }>() : {};
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
      const body = await request.json<{ category?: string; amount?: number; cityId?: string; correlationId?: string }>();
      const amount = Number(body.amount);
      const category = body.category?.trim() || 'public-services';
      const cityId = body.cityId?.trim() || 'CITY-0084';
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100000 || correlationId.length > 120) return Response.json({ ok: false, error: 'Treasury amount and correlation ID are invalid' }, { status: 400 });
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
      const body = await request.json<{ amount?: number; correlationId?: string }>();
      const amount = Math.round(Number(body.amount) * 100) / 100;
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!Number.isFinite(amount) || amount <= 0 || amount > 10000 || correlationId.length > 120) return Response.json({ ok: false, error: 'Contribution amount or correlation ID is invalid' }, { status: 400 });
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
      const body = await request.json<{ machineType?: string; correlationId?: string }>();
      const type = body.machineType?.trim() ?? '';
      const spec = MACHINE_CATALOG[type];
      if (!spec) return Response.json({ ok: false, error: 'Unsupported machine type' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => acquireMachinePostgres(repository, { ownerId: viewer.id, machineType: type, name: `${type.replaceAll('-', ' ')} ${viewer.id.slice(-4)}`, credit: spec.credit, material: spec.material, capacity: spec.capacity, output: spec.output, inputResource: 'energy', correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Machine acquisition failed' }, { status: 409 });
      }
    }
    if (url.pathname === '/api/production/catalog' && request.method === 'GET') {
      return Response.json({ sectors: [
        { id: 'energy', name: 'Energy', output: 'energy', machineTypes: ['energy-array'], acquisition: MACHINE_CATALOG['energy-array'] },
        { id: 'extraction', name: 'Extraction', output: 'material', machineTypes: ['extractor'], acquisition: MACHINE_CATALOG.extractor },
        { id: 'components', name: 'Components', output: 'components', machineTypes: ['fabricator'], acquisition: MACHINE_CATALOG.fabricator },
        { id: 'machines', name: 'Machines', output: 'components', machineTypes: ['assembly-line'] },
        { id: 'maintenance', name: 'Maintenance', output: 'components', machineTypes: ['service-robot'] },
        { id: 'housing', name: 'Housing', output: 'components', machineTypes: ['housing-fabricator'], acquisition: MACHINE_CATALOG['housing-fabricator'] },
        { id: 'compute', name: 'Compute', output: 'compute', machineTypes: ['compute-node'], acquisition: MACHINE_CATALOG['compute-node'] },
        { id: 'r-and-d', name: 'R&D', output: 'compute', machineTypes: ['research-cluster'], acquisition: MACHINE_CATALOG['research-cluster'] },
      ], rules: { serverAuthoritative: true, productionRequiresUtilization: true, depreciationApplied: true }, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/technology' && request.method === 'GET') {
      const result = await withRepository(env, (repository) => listTechnologyPostgres(repository));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    }
    if (url.pathname === '/api/technology/projects' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; budget?: number; focus?: string; correlationId?: string }>();
      const name = body.name?.trim();
      const budget = Math.round(Number(body.budget ?? 240) * 100) / 100;
      const focus = body.focus?.trim() ?? 'efficiency';
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!name || name.length < 3 || name.length > 120 || !Number.isFinite(budget) || budget < 240 || budget > 100000 || !['efficiency','durability','safety','cost'].includes(focus) || correlationId.length > 120) return Response.json({ ok: false, error: 'Research parameters are invalid' }, { status: 400 });
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
      const body = await request.json<{ amount?: number; correlationId?: string }>();
      const amount = Number(body.amount ?? 240);
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!Number.isFinite(amount) || amount <= 0 || correlationId.length > 120) return Response.json({ ok: false, error: 'Funding parameters are invalid' }, { status: 400 });
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
      const body = await request.json<{ licenseeId?: string; royaltyRate?: number; licenseFee?: number; otp?: string }>();
      const licenseeId = body.licenseeId || viewer.id;
      const royaltyRate = Number(body.royaltyRate ?? 0.05);
      const licenseFee = Math.round(Number(body.licenseFee ?? (licenseeId === viewer.id ? 0 : 100)) * 100) / 100;
      const correlationId = crypto.randomUUID();
      if (!Number.isFinite(royaltyRate) || royaltyRate < 0 || royaltyRate > 1 || !Number.isFinite(licenseFee) || licenseFee < 0 || licenseFee > 100000 || (licenseeId !== viewer.id && licenseFee < 50)) return Response.json({ ok: false, error: 'License terms are invalid' }, { status: 400 });
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
      const body = await request.json<{ otp?: string; reason?: string }>();
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
      const body = await request.json<{ kind?: string; counterpartyId?: string; title?: string; terms?: Record<string, unknown>; amount?: number; durationDays?: number; correlationId?: string }>();
      const kind = body.kind?.trim() ?? '';
      const counterpartyId = body.counterpartyId?.trim() ?? '';
      const title = body.title?.trim() ?? '';
      const amount = Math.round(Number(body.amount ?? 0) * 100) / 100;
      const durationDays = Number(body.durationDays ?? 30);
      if (!['employment', 'intellectual_service', 'capacity', 'strategic'].includes(kind)) return Response.json({ ok: false, error: 'Unsupported contract kind' }, { status: 400 });
      const counterparty = await withRepository(env, (repository) => repository.query("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [counterpartyId]));
      if (!counterpartyId || counterpartyId === viewer.id || !counterparty?.rows[0]) return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
      if (title.length < 3 || title.length > 140 || !Number.isFinite(amount) || amount < 0 || amount > 100000 || !Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) return Response.json({ ok: false, error: 'Contract terms are outside engine bounds' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createContractPostgres(repository, { proposerId: viewer.id, kind, counterpartyId, title, terms: body.terms ?? {}, amount, durationDays, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract creation failed' }, { status: 409 });
      }
    }
    const contractActionMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(accept|cancel)$/);
    if (contractActionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      try {
        const result = contractActionMatch[2] === 'cancel'
          ? await withRepository(env, (repository) => cancelContractPostgres(repository, contractActionMatch[1], viewer.id))
          : await withRepository(env, (repository) => acceptContractPostgres(repository, contractActionMatch[1], viewer.id));
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
          const body = await request.json<{ reason?: string }>();
          const reason = body.reason?.trim() ?? '';
          if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
          const result = await withRepository(env, (repository) => openDisputePostgres(repository, { contractId: contractDisputeMatch[1], claimantId: viewer.id, reason }));
          if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
          return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyOpen ? 200 : 201 });
        }
        const body = await request.json<{ outcome?: string; resolution?: string }>();
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
    if (url.pathname === '/api/finance/recover' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const parsed = await parseJsonBody<{ institutionId?: string; amount?: number; otp?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for financial recovery' }, { status: 401 });
      const institutionId = body.institutionId?.trim() ?? '';
      const amount = Math.round(Number(body.amount) * 100) / 100;
      if (!institutionId || !Number.isFinite(amount) || amount <= 0 || amount > 100000) return Response.json({ ok: false, error: 'Recovery amount must be between 0 and 100,000 Credits' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => recoverInstitutionPostgres(repository, { humanId: viewer.id, institutionId, amount, correlationId: crypto.randomUUID() }));
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
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Public spending amount must be positive' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
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
          repository.query("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1"),
        ]);
        let feeRate = 0;
        const value = rule.rows[0]?.value_json;
        if (value) {
          try {
            const parsed = typeof value === 'string' ? JSON.parse(value) : value;
            if (typeof parsed?.feeRate === 'number' && parsed.feeRate >= 0 && parsed.feeRate <= 0.05) feeRate = parsed.feeRate;
          } catch { /* safe zero fee */ }
        }
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
      const body = await request.json<{ product?: string; quantity?: number; limitPrice?: number; side?: string; correlationId?: string }>();
      const product = body.product;
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = Number(body.quantity);
      const limitPrice = Number(body.limitPrice);
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '') || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0) return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
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
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '')) return Response.json({ ok: false, error: 'Unknown product' }, { status: 400 });
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
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
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
    if (url.pathname === '/api/businesses' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ name?: string; sector?: string; correlationId?: string }>();
      const name = body.name?.trim();
      const sector = body.sector?.trim() ?? 'maintenance';
      const sectors = ['energy', 'extraction', 'components', 'machines', 'maintenance', 'housing', 'compute', 'r-and-d'];
      if (!name || name.length < 3 || name.length > 80 || !sectors.includes(sector)) return Response.json({ ok: false, error: 'Business name or sector is invalid' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      try {
        const result = await withRepository(env, (repository) => createBusinessPostgres(repository, { ownerId: viewer.id, name, sector, correlationId }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Business registration failed';
        return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /requires/i.test(message) ? 409 : 400 });
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
      const body = await request.json<{ policy?: string }>();
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
      const body = await request.json<{ managerId?: string }>();
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
      const body = await request.json<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>();
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
      const body = await request.json<{ businessId?: string; recipientId?: string; shares?: number; correlationId?: string }>();
      const recipientId = body.recipientId?.trim() ?? '';
      const shares = Number(body.shares);
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || correlationId.length > 160) return Response.json({ ok: false, error: 'Invalid share transfer terms' }, { status: 400 });
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
      const body = await request.json<{ recipientId?: string; shares?: number; pricePerShare?: number; correlationId?: string }>();
      const recipientId = body.recipientId?.trim() ?? '';
      const shares = Number(body.shares);
      const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000 || correlationId.length > 160) return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
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
      const body = await request.json<{ name?: string; estatePeriodDays?: number; successorHumanId?: string }>();
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
      const body = await request.json<{ amount?: number; correlationId?: string }>();
      const amount = Number(body.amount ?? 10);
      const correlationId = String(body.correlationId ?? '').trim();
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Maintenance amount must be positive' }, { status: 400 });
      if (!correlationId || correlationId.length > 160) return Response.json({ ok: false, error: 'A valid maintenance correlationId is required' }, { status: 400 });
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
      const body = await request.json<{ otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for decommissioning an asset' }, { status: 401 });
      try {
        const result = await withRepository(env, (repository) => recycleMachinePostgres(repository, { machineId: decommissionMatch[1], ownerId: viewer.id }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Machine recycling failed';
        return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
      }
    }
    const utilizationMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/utilization$/);
    if (utilizationMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ utilization?: number }>();
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
      const body = await request.json<{ otp?: string; correlationId?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for machine upgrades' }, { status: 401 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 160) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
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
      const body = await request.json<{ buyerId?: string; price?: number; otp?: string; correlationId?: string }>();
      const buyerId = body.buyerId?.trim();
      const price = Math.round(Number(body.price) * 100) / 100;
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (!buyerId || buyerId === viewer.id || !Number.isFinite(price) || price <= 0 || price > 1000000) return Response.json({ ok: false, error: 'Buyer and sale price are invalid' }, { status: 400 });
      if (correlationId.length > 160) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
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
      const outboxDelivered = await deliverOutbox(repository, (outboxEvent) => env.MARKET_COORDINATOR.getByName('events-global').broadcast(outboxEvent.payload));
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
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: {
        'Access-Control-Allow-Origin': request.headers.get('Origin') ?? '*',
        'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Expose-Headers': 'X-Request-ID',
        'Access-Control-Max-Age': '86400',
        'X-Request-ID': requestId,
      } });
    }
    const url = new URL(request.url);
    const isDataRequest = url.pathname.startsWith('/api/') || url.pathname.startsWith('/edge/') || url.pathname === '/health';
    if (isDataRequest) authorityMode(env);
    const response = isDataRequest
      ? await worker.fetch(request, env, ctx)
      : url.pathname === '/'
        ? await env.ASSETS.fetch(new Request(new URL('/landing.html', request.url), request))
      : url.pathname === '/landing'
        ? await env.ASSETS.fetch(new Request(new URL(`/landing.html?v=${WEB_ASSET_VERSION}`, request.url), request))
      : url.pathname === '/app'
          ? await env.ASSETS.fetch(new Request(new URL(`/app.html?v=${WEB_ASSET_VERSION}`, request.url), request))
        : url.pathname.startsWith('/app/')
          ? await env.ASSETS.fetch(new Request(new URL(`${url.pathname.slice(4)}?v=${WEB_ASSET_VERSION}`, request.url), request))
          : await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);
    const origin = request.headers.get('Origin');
    if (origin === 'https://earth-client.pages.dev' || origin?.endsWith('.earth-client.pages.dev')) {
      headers.set('Access-Control-Allow-Origin', origin);
      headers.set('Vary', 'Origin');
    }
    headers.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    headers.set('Access-Control-Expose-Headers', 'X-Request-ID');
    headers.set('X-Request-ID', requestId);
    headers.set('X-EARTH-API-Version', '2026-08');
    if (response.status >= 400 && response.headers.get('content-type')?.includes('application/json')) {
      try {
        const payload = await response.clone().json() as Record<string, unknown>;
        if (payload && typeof payload === 'object') {
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
          headers.set('content-type', 'application/json');
          return new Response(JSON.stringify(payload), { status: response.status, statusText: response.statusText, headers });
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
