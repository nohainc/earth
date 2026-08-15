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
import { auditWorld as auditWorldPostgres, getServiceStatus as getServiceStatusPostgres, listAuthorityEvents as listAuthorityEventsPostgres, listEvents as listEventsPostgres, listGovernanceProposals as listGovernanceProposalsPostgres, listGovernanceRules as listGovernanceRulesPostgres, listHistory as listHistoryPostgres, listInstitutions as listInstitutionsPostgres, listMembershipEvents as listMembershipEventsPostgres, listNotifications as listNotificationsPostgres, listProductionEvents as listProductionEventsPostgres, listOwnershipEvents as listOwnershipEventsPostgres, listRankings as listRankingsPostgres, listTechnology as listTechnologyPostgres, markNotificationRead as markNotificationReadPostgres, readBusiness as readBusinessPostgres } from './read-postgres';

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
async function votingWeight(env: Env, humanId: string, institutionId: string): Promise<number> {
  const institution = await env.DB.prepare('SELECT kind FROM institutions WHERE id = ?').bind(institutionId).first<{ kind: string }>();
  if (institution?.kind !== 'OUC') return 1;
  const delegated = await env.DB.prepare("SELECT delegator_id FROM authority_delegations WHERE institution_id = ? AND delegate_id = ? AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1").bind(institutionId, humanId).first<{ delegator_id: string }>();
  const representation = await env.DB.prepare('SELECT corporations.member_count, cities.residents FROM memberships LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE memberships.human_id = ?').bind(delegated?.delegator_id ?? humanId).first<{ member_count: number | null; residents: number | null }>();
  const population = Number(representation?.member_count ?? representation?.residents ?? 0);
  return Math.round((1 + Math.min(2, population / 100)) * 1000) / 1000;
}
async function resolveGovernanceProposals(env: Env): Promise<void> {
  await env.DB.prepare("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND closes_at <= CURRENT_TIMESTAMP").run();
  const open = await env.DB.prepare("SELECT id, institution_id, quorum, approval_threshold, implementation_delay_days FROM proposals WHERE status = 'closed' AND outcome = 'pending'").all<{ id: string; institution_id: string; quorum: number; approval_threshold: number; implementation_delay_days: number }>();
  for (const proposal of open.results) {
    const counts = await env.DB.prepare('SELECT choice, COALESCE(SUM(weight), 0) AS weight FROM ballots WHERE proposal_id = ? GROUP BY choice').bind(proposal.id).all<{ choice: string; weight: number }>();
    const totals = Object.fromEntries(counts.results.map((row) => [row.choice, Number(row.weight)]));
    const eligible = await env.DB.prepare("SELECT COUNT(*) AS count FROM humans WHERE life_status = 'active'").first<{ count: number }>();
    const representation = await env.DB.prepare("SELECT COALESCE(SUM(1 + CASE WHEN memberships.corporation_id IS NOT NULL THEN MIN(2, corporations.member_count / 100.0) WHEN memberships.city_id IS NOT NULL THEN MIN(2, cities.residents / 100.0) ELSE 0 END), 0) AS weight FROM humans LEFT JOIN memberships ON memberships.human_id = humans.id LEFT JOIN corporations ON corporations.id = memberships.corporation_id LEFT JOIN cities ON cities.id = memberships.city_id WHERE humans.life_status = 'active'").first<{ weight: number }>();
    const eligibleWeight = Math.max(Number(eligible?.count ?? 0), Number(representation?.weight ?? 0));
    const cast = (totals.support ?? 0) + (totals.oppose ?? 0) + (totals.abstain ?? 0);
    const decisive = (totals.support ?? 0) + (totals.oppose ?? 0);
    const quorumMet = eligibleWeight > 0 && cast / eligibleWeight >= Number(proposal.quorum);
    const passed = quorumMet && decisive > 0 && (totals.support ?? 0) / decisive >= Number(proposal.approval_threshold);
    const outcome = !quorumMet ? 'no_quorum' : passed ? 'passed' : 'rejected';
    const implementationAt = passed ? `+${Math.max(0, Number(proposal.implementation_delay_days))} days` : null;
    await env.DB.prepare("UPDATE proposals SET outcome = ?, resolved_at = CURRENT_TIMESTAMP, implementation_at = CASE WHEN ? = 'passed' THEN datetime(CURRENT_TIMESTAMP, ?) ELSE NULL END WHERE id = ?").bind(outcome, outcome, implementationAt ?? '+0 days', proposal.id).run();
  }
}
async function hasActiveRole(env: Env, humanId: string, roleIds: string[]): Promise<boolean> {
  if (!roleIds.length) return false;
  const placeholders = roleIds.map(() => '?').join(',');
  const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
  const row = await env.DB.prepare(`SELECT id FROM role_assignments WHERE (human_id = ? OR role_id IN (SELECT role_id FROM authority_delegations WHERE delegate_id = ? AND status = 'active' AND ends_game_day > ?)) AND status = 'active' AND ends_game_day > ? AND role_id IN (${placeholders}) LIMIT 1`).bind(humanId, humanId, day, day, ...roleIds).first();
  return Boolean(row);
}
async function eligibleForInstitution(env: Env, humanId: string, institutionId: string): Promise<boolean> {
  const world = await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>();
  const human = await env.DB.prepare('SELECT political_eligibility_game_day FROM humans WHERE id = ?').bind(humanId).first<{ political_eligibility_game_day: number }>();
  if (Number(world?.game_day ?? 0) < Number(human?.political_eligibility_game_day ?? 0)) return false;
  const institution = await env.DB.prepare('SELECT kind FROM institutions WHERE id = ?').bind(institutionId).first<{ kind: string }>();
  if (!institution) return false;
  if (institution.kind === 'OUC') return Boolean(await env.DB.prepare("SELECT id FROM role_assignments WHERE role_id = 'ROLE-OUC-DELEGATE' AND human_id = ? AND status = 'active' UNION ALL SELECT id FROM authority_delegations WHERE role_id = 'ROLE-OUC-DELEGATE' AND delegate_id = ? AND status = 'active' LIMIT 1").bind(humanId, humanId).first());
  if (institution.kind === 'CORPORATION') return Boolean(await env.DB.prepare('SELECT human_id FROM memberships WHERE human_id = ? AND corporation_id = ?').bind(humanId, institutionId).first());
  if (institution.kind === 'CITY') return Boolean(await env.DB.prepare('SELECT human_id FROM memberships WHERE human_id = ? AND city_id = ?').bind(humanId, institutionId).first());
  return false;
}
async function canExerciseDelegatedRole(env: Env, humanId: string, institutionId: string): Promise<boolean> {
  return Boolean(await env.DB.prepare("SELECT id FROM authority_delegations WHERE institution_id = ? AND delegate_id = ? AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1").bind(institutionId, humanId).first()) || await eligibleForInstitution(env, humanId, institutionId);
}
async function marketFeeRate(env: Env): Promise<number> {
  const rule = await env.DB.prepare("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string }>();
  if (!rule?.value_json) return 0;
  try {
    const value = JSON.parse(rule.value_json) as { feeRate?: number };
    return typeof value.feeRate === 'number' && value.feeRate >= 0 && value.feeRate <= 0.05 ? value.feeRate : 0;
  } catch (_error) { return 0; }
}
async function marketFairAllocation(env: Env): Promise<boolean> {
  const rule = await env.DB.prepare("SELECT value_json FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'market' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string }>();
  if (!rule?.value_json) return true;
  try {
    const value = JSON.parse(rule.value_json) as { fairAllocation?: boolean };
    return value.fairAllocation !== false;
  } catch (_error) { return true; }
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
  const path = action === 'verify_email' ? '/api/auth/verify-email' : '/api/auth/reset-password';
  const subject = action === 'verify_email' ? 'Verify your EARTH identity' : 'Reset your EARTH password';
  const text = `${subject}\n\nOpen this link to continue: https://earthuc.com${path}?token=${encodeURIComponent(token)}\n\nThis link expires soon and can only be used once.`;
  try {
    const delivery = await env.EMAIL.send({ to: email, from: { email: env.EMAIL_FROM, name: 'EARTH Identity' }, replyTo: env.EMAIL_REPLY_TO, subject, text, html: `<p>${subject}</p><p><a href="https://earthuc.com${path}?token=${encodeURIComponent(token)}">Continue securely</a></p><p>This link expires soon and can only be used once.</p>` });
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
      const body = await request.json<{ email?: string; password?: string; passwordConfirmation?: string; displayName?: string }>();
      const email = body.email?.trim().toLowerCase();
      const displayName = body.displayName?.trim();
      const password = body.password ?? '';
      if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return Response.json({ ok: false, error: 'A valid email is required' }, { status: 400 });
      if (!displayName || displayName.length < 2 || displayName.length > 80) return Response.json({ ok: false, error: 'Display name must be 2–80 characters' }, { status: 400 });
      if (password.length < 12) return Response.json({ ok: false, error: 'Password must be at least 12 characters' }, { status: 400 });
      if (password !== (body.passwordConfirmation ?? '')) return Response.json({ ok: false, error: 'Passwords do not match' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => registerIdentityPostgres(repository, { email, displayName, password }));
          if (result) {
            try {
              const identity = result.human as { id: string; email: string };
              await issueActionToken(env, identity.id, 'verify_email', identity.email);
            } catch {
              return Response.json({ ok: false, error: 'Identity created, but the verification email could not be sent. Please retry shortly.' }, { status: 503 });
            }
            return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Identity creation failed';
          return Response.json({ ok: false, error: message }, { status: /already registered/i.test(message) ? 409 : 400 });
        }
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
      const body = await request.json<{ email?: string; password?: string; otp?: string }>();
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
      if (authorityMode(env) === 'postgres') {
        try {
          const snapshot = await withRepository(env, (repository) => worldSnapshotPostgres(repository, viewerId));
          if (snapshot) return Response.json(snapshot);
        } catch (error) {
          console.error(JSON.stringify({ event: 'world_snapshot_failed', code: 'WORLD_SNAPSHOT_UNAVAILABLE', message: error instanceof Error ? error.message : 'unknown' }));
          return Response.json({ ok: false, code: 'WORLD_SNAPSHOT_UNAVAILABLE', error: 'World snapshot is temporarily unavailable', persistence: 'planetscale-postgres' }, { status: 503 });
        }
      }
      const [world, human, institutions, resources, business, technology, proposals, machines, account, ballots, succession, membership, prices, ledger, cityMetrics, corporationMetrics, personalFinance, contracts] = await Promise.all([
        env.DB.prepare('SELECT * FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM institutions').all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind(viewerId).all(),
        env.DB.prepare("SELECT businesses.*, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id AND holder_id = ?), 0) AS owned_shares, COALESCE((SELECT SUM(shares) FROM business_shares WHERE business_id = businesses.id), 0) AS total_issued_shares, (SELECT holder_id FROM business_shares WHERE business_id = businesses.id ORDER BY shares DESC, holder_id LIMIT 1) AS controlling_human_id, COALESCE(business_constitutions.version, 1) AS constitution_version, COALESCE(business_constitutions.shareholder_vote_threshold, 0.5) AS shareholder_vote_threshold, COALESCE(business_constitutions.board_approval_threshold, 0.5) AS board_approval_threshold, COALESCE(business_constitutions.dilution_notice_days, 3) AS dilution_notice_days, COALESCE(business_management.manager_id, businesses.owner_id) AS manager_id, COALESCE(business_financials.revenue, 0) AS revenue, COALESCE(business_financials.operating_costs, 0) AS operating_costs, COALESCE(business_financials.profit, 0) AS profit FROM businesses LEFT JOIN business_constitutions ON business_constitutions.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id LEFT JOIN business_financials ON business_financials.business_id = businesses.id WHERE businesses.owner_id = ? OR business_management.manager_id = ? OR EXISTS (SELECT 1 FROM business_shares viewer_shares WHERE viewer_shares.business_id = businesses.id AND viewer_shares.holder_id = ?) ORDER BY businesses.id LIMIT 1").bind(viewerId, viewerId, viewerId, viewerId).first(),
        env.DB.prepare('SELECT * FROM technologies WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM proposals ORDER BY closes_at ASC LIMIT 20').all(),
        env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind(viewerId).all(),
        env.DB.prepare('SELECT balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(viewerId, 'CREDIT').first<{ balance: number }>(),
        env.DB.prepare('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice').all(),
        env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM market_prices ORDER BY product').all(),
        env.DB.prepare('SELECT * FROM ledger_entries ORDER BY created_at DESC LIMIT 25').all(),
        env.DB.prepare("SELECT * FROM cities WHERE id = COALESCE((SELECT city_id FROM memberships WHERE human_id = ? AND city_id IS NOT NULL), 'CITY-0084')").bind(viewerId).first(),
        env.DB.prepare("SELECT * FROM corporations WHERE id = COALESCE((SELECT corporation_id FROM memberships WHERE human_id = ? AND corporation_id IS NOT NULL), 'CORP-001')").bind(viewerId).first(),
        env.DB.prepare('SELECT * FROM personal_financial_states WHERE human_id = ?').bind(viewerId).first(),
        env.DB.prepare("SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = ? OR negotiated_contracts.counterparty_id = ? ORDER BY negotiated_contracts.created_at DESC LIMIT 30").bind(viewerId, viewerId).all(),
      ]);
      const institutionRows = institutions.results as Array<Record<string, unknown>>;
      const byKind = (kind: string) => institutionRows.find((item) => item.kind === kind) ?? {};
      const resourceMap = Object.fromEntries((resources.results as Array<Record<string, unknown>>).map((item) => [item.resource, item.amount]));
      const voteCounts = (ballots.results as Array<Record<string, unknown>>).reduce<Record<string, Record<string, number>>>((all, item) => {
        const proposalId = String(item.proposal_id);
        all[proposalId] ??= {};
        all[proposalId][String(item.choice)] = Number(item.count);
        return all;
      }, {});
      const marketProducts = Object.fromEntries((prices.results as Array<Record<string, unknown>>).map((item) => [item.product, { price: item.price, supply: item.supply, demand: item.demand }]));
      const marketFee = await marketFeeRate(env);
      const rankings = await Promise.all([
        env.DB.prepare('SELECT id, residents, treasury, housing_capacity, energy_capacity FROM cities ORDER BY treasury DESC LIMIT 10').all(),
        env.DB.prepare('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT 10').all(),
      ]);
      const [book, trades] = await Promise.all([
        env.DB.prepare("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product").all(),
        env.DB.prepare('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product').all(),
      ]);
      const ownOrders = await env.DB.prepare("SELECT id, product, side, quantity, filled_quantity, limit_price, status, created_at FROM market_orders WHERE human_id = ? AND status IN ('open','partial') ORDER BY created_at DESC LIMIT 50").bind(viewerId).all();
      const productionEvents = await env.DB.prepare('SELECT production_events.*, machines.name AS machine_name FROM production_events JOIN machines ON machines.id = production_events.machine_id WHERE production_events.owner_id = ? ORDER BY production_events.game_day DESC, production_events.created_at DESC LIMIT 30').bind(viewerId).all();
      const aiAssistants = await env.DB.prepare('SELECT id, tier, policy, enabled FROM ai_assistants WHERE owner_id = ? ORDER BY id').bind(viewerId).all();
      const aiRecommendations = [
        ...(machines.results as Array<Record<string, unknown>>).filter((machine) => Number(machine.condition ?? 100) < 40).map((machine) => ({ type: 'maintenance', priority: 'high', subject: machine.id, message: `${machine.name} is below 40% condition; allocate Components or enable maintenance automation.` })),
        ...(machines.results as Array<Record<string, unknown>>).filter((machine) => Number(machine.utilization ?? 0) > 0 && Number(machine.condition ?? 100) < 70).map((machine) => ({ type: 'utilization', priority: 'medium', subject: machine.id, message: `Reduce utilization for ${machine.name} until its condition improves.` })),
        ...(Number(cityMetrics?.health_capacity ?? 0) / 100 < 0.5 ? [{ type: 'services', priority: 'high', subject: 'CITY-HEALTH', message: 'Health service is critical; propose or fund additional city health capacity.' }] : []),
      ];
      const communities = await env.DB.prepare('SELECT id, name, status FROM communities ORDER BY name LIMIT 20').all();
      const technologyRegistry = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS count FROM patents WHERE technology_id = ? AND status = ?').bind(technology?.id ?? '', 'active').first(),
        env.DB.prepare('SELECT COUNT(*) AS count FROM technology_licenses WHERE patent_id IN (SELECT id FROM patents WHERE technology_id = ?) AND status = ?').bind(technology?.id ?? '', 'active').first(),
      ]);
      const finance = await env.DB.prepare('SELECT scope, category, rate, version FROM tax_rules WHERE active = 1 ORDER BY id').all();
      const liquidity = await env.DB.prepare("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index").first<{ active_humans: number; money_supply: number; living_cost_index: number }>();
      const liquidityTarget = Number(liquidity?.active_humans ?? 0) * Math.max(0.5, Number(liquidity?.living_cost_index ?? 1)) * 100;
      const liquiditySupply = Number(liquidity?.money_supply ?? 0);
      const liquidityStatus = liquiditySupply < liquidityTarget * 0.8 ? 'below-corridor' : liquiditySupply > liquidityTarget * 1.2 ? 'above-corridor' : 'inside-corridor';
      const audit = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM account_balances WHERE balance < 0').first<{ invalid: number }>(),
        env.DB.prepare("SELECT COUNT(*) AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account").first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM machines WHERE condition < 0 OR condition > 100').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM corporations WHERE member_count != (SELECT COUNT(*) FROM memberships WHERE memberships.corporation_id = corporations.id)').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM cities WHERE residents != (SELECT COUNT(*) FROM memberships WHERE memberships.city_id = cities.id)').first<{ invalid: number }>(),
      ]);
      const financialStates = await env.DB.prepare('SELECT institution_id, institution_kind, status, since_game_day, recovery_game_day FROM financial_states ORDER BY institution_kind, institution_id').all();
      const roles = await env.DB.prepare("SELECT institution_roles.id, institution_roles.name, institution_roles.institution_id, role_assignments.human_id, role_assignments.started_game_day, role_assignments.ends_game_day, role_assignments.status AS assignment_status FROM institution_roles LEFT JOIN role_assignments ON role_assignments.role_id = institution_roles.id AND role_assignments.status = 'active' WHERE institution_roles.status = 'active' ORDER BY institution_roles.institution_id, institution_roles.id").all();
      const serviceRatios = cityMetrics ? {
        housing: Math.min(1, Number(cityMetrics.housing_capacity ?? 0) / Math.max(1, Number(cityMetrics.residents ?? 0))),
        energy: Math.min(1, Number(cityMetrics.energy_capacity ?? 0) / Math.max(1, Number(cityMetrics.residents ?? 0))),
        connectivity: Math.min(1, Number(cityMetrics.connectivity_capacity ?? 0) / Math.max(1, Number(cityMetrics.residents ?? 0))),
        health: Math.min(1, Number(cityMetrics.health_capacity ?? 0) / 100),
      } : { housing: 0.75, energy: 0.75, connectivity: 0.75, health: 0.5 };
      const serviceStatus = {
        housing: serviceRatios.housing >= 1 ? 'normal' : serviceRatios.housing >= 0.75 ? 'basic' : 'critical',
        utilities: serviceRatios.energy >= 1 ? 'normal' : serviceRatios.energy >= 0.75 ? 'basic' : 'critical',
        connectivity: serviceRatios.connectivity >= 1 ? 'normal' : serviceRatios.connectivity >= 0.75 ? 'basic' : 'critical',
        health: serviceRatios.health >= 0.8 ? 'normal' : serviceRatios.health >= 0.5 ? 'basic' : 'critical',
      };
      const cityQualification = cityMetrics ? {
        activePopulation: Number(cityMetrics.residents ?? 0) >= 10,
        housing: Number(cityMetrics.housing_capacity ?? 0) >= Number(cityMetrics.residents ?? 0),
        energy: Number(cityMetrics.energy_capacity ?? 0) >= Number(cityMetrics.residents ?? 0),
        connectivity: Number(cityMetrics.connectivity_capacity ?? 0) >= Number(cityMetrics.residents ?? 0),
        health: Number(cityMetrics.health_capacity ?? 0) >= 50,
        treasury: Number(cityMetrics.treasury ?? 0) >= 0,
        governance: true,
      } : {};
      const corporationQualification = corporationMetrics ? {
        activeMembership: Number(corporationMetrics.member_count ?? 0) >= 30,
        recognizedCity: Boolean(await env.DB.prepare('SELECT id FROM cities WHERE id = (SELECT city_id FROM memberships WHERE corporation_id = ? AND city_id IS NOT NULL LIMIT 1)').bind(corporationMetrics.id).first()),
        treasury: Number(corporationMetrics.treasury ?? 0) >= 1000,
        constitution: Number(corporationMetrics.constitution_version ?? 0) >= 1,
        governance: true,
      } : {};
      const history = await Promise.all([
        env.DB.prepare('SELECT id, game_day, event_type, title, details FROM world_events ORDER BY game_day DESC, created_at DESC LIMIT 12').all(),
        env.DB.prepare('SELECT game_day, ranking_type, entity_id, rank, score FROM rankings_snapshots ORDER BY game_day DESC, ranking_type, rank LIMIT 20').all(),
      ]);
      return Response.json({
        clock: { day: world?.game_day ?? 184, minute: world?.game_minute ?? 0, realSecondsPerGameMinute: 1 },
        world: { health: world?.health ?? 68, batch: world?.market_batch_seconds ?? 498, livingCostIndex: world?.living_cost_index ?? 1, essentialServicesIndex: world?.essential_services_index ?? 0.68, serviceRatios, serviceStatus, cityQualification, corporationQualification },
        human: { id: human?.id, name: human?.display_name, credits: account?.balance ?? 0, standing: human?.standing ?? 0, legacy: human?.legacy ?? 0, ageYears: human?.age_years ?? 31, politicalEligibilityGameDay: human?.political_eligibility_game_day ?? 0, politicalMaturity: Number(world?.game_day ?? 0) >= Number(human?.political_eligibility_game_day ?? 0) },
        life: { generation: 1, status: human?.life_status ?? 'active', ageYears: human?.age_years ?? 31, successor: succession ?? null, estatePeriodDays: succession?.estate_period_days ?? 30 },
        membership: membership ?? null,
        institutions: { ouc: byKind('OUC'), corporation: { ...byKind('CORPORATION'), ...corporationMetrics }, city: { ...byKind('CITY'), ...cityMetrics }, business: byKind('BUSINESS') },
        resources: resourceMap, business: business ?? {}, market: { products: marketProducts, book: book.results, trades: trades.results, orders: ownOrders.results, feeRate: marketFee, lastSettlement: null },
        governance: { proposals: (proposals.results as Array<Record<string, unknown>>).map((proposal) => ({ ...proposal, votes: voteCounts[String(proposal.id)] ?? { support: 0, oppose: 0, abstain: 0 }, ballots: {} })) },
        technology: { research: technology ?? {}, activePatents: Number(technologyRegistry[0]?.count ?? 0), activeLicenses: Number(technologyRegistry[1]?.count ?? 0) }, machines: machines.results, productionEvents: productionEvents.results, aiAssistants: aiAssistants.results, aiRecommendations, ledgerEntries: ledger.results,
        publicActivity: [{ type: 'world_clock', day: world?.game_day ?? 184 }, { type: 'research_progress', progress: technology?.progress ?? 0 }, { type: 'market_cycle', batch: world?.market_batch_seconds ?? 498 }],
        rankings: { cities: rankings[0].results, corporations: rankings[1].results },
        history: { events: history[0].results, rankings: history[1].results },
        financeStatus: financialStates.results,
        personalFinance: personalFinance ?? { status: 'active', protected_credits: 100 },
        contracts: contracts.results,
        roles: roles.results,
        communities: communities.results,
        audit: { balancesNonNegative: Number(audit[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(audit[1]?.invalid ?? 0) === 0, machineConditionsBounded: Number(audit[2]?.invalid ?? 0) === 0, corporationMemberCountsConsistent: Number(audit[3]?.invalid ?? 0) === 0, cityResidentCountsConsistent: Number(audit[4]?.invalid ?? 0) === 0 },
        finance: { taxRules: finance.results, liquidity: { activeHumans: Number(liquidity?.active_humans ?? 0), moneySupply: liquiditySupply, target: liquidityTarget, corridor: { low: liquidityTarget * 0.8, high: liquidityTarget * 1.2 }, status: liquidityStatus } },
        persistence: 'cloudflare-d1'
      });
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
      const priorFormation = await env.DB.prepare("SELECT institution_id FROM membership_events WHERE reason = 'community_formation' AND institution_type = 'COMMUNITY' AND human_id = ? AND id = ?").bind(founderId, correlationId).first<{ institution_id: string }>();
      if (priorFormation) return Response.json({ ok: true, alreadyProcessed: true, community: await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(priorFormation.institution_id).first(), correlationId, persistence: 'cloudflare-d1' });
      const communityId = `COMM-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO communities (id, name, founder_id, shared_credits) VALUES (?, ?, ?, 0)').bind(communityId, name, founderId),
        env.DB.prepare('INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES (?, ?, ?, ?)').bind(communityId, founderId, 'founder', day),
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(correlationId, founderId, 'COMMUNITY', communityId, 'joined', day, 'community_formation'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`COMMUNITY-FOUNDED-${founderId}-${communityId}`, founderId, 'community', 'Community founded', `You founded community ${communityId}.`, communityId),
      ]);
      return Response.json({ ok: true, community: await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(communityId).first(), persistence: 'cloudflare-d1' });
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
      const community = await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(communityId).first();
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      const members = await env.DB.prepare('SELECT community_id, human_id, role, joined_game_day FROM community_members WHERE community_id = ? ORDER BY joined_game_day, human_id').bind(communityId).all();
      return Response.json({ community, members: members.results, persistence: 'cloudflare-d1' });
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
      const [community, human] = await Promise.all([
        env.DB.prepare('SELECT id, status FROM communities WHERE id = ?').bind(communityId).first<{ id: string; status: string }>(),
        env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first(),
      ]);
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      if (community.status !== 'active') return Response.json({ ok: false, error: 'Community is not active' }, { status: 409 });
      if (!human) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const existing = await env.DB.prepare('SELECT community_id FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId).first();
      if (request.method === 'DELETE') {
        if (!existing) return Response.json({ ok: false, error: 'Human is not a community member' }, { status: 409 });
        await env.DB.batch([
          env.DB.prepare('DELETE FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId),
          env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?), ?)').bind(crypto.randomUUID(), humanId, 'COMMUNITY', communityId, 'left', 'WORLD', 'voluntary_departure'),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`COMMUNITY-LEFT-${humanId}-${communityId}`, humanId, 'community', 'Community left', `You left community ${communityId}.`, communityId),
        ]);
        return Response.json({ ok: true, membership: null, persistence: 'cloudflare-d1' });
      }
      if (existing) return Response.json({ ok: false, error: 'Human is already a community member' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO community_members (community_id, human_id, role, joined_game_day) VALUES (?, ?, ?, ?)').bind(communityId, humanId, 'member', day),
        env.DB.prepare('INSERT INTO membership_events (id, human_id, institution_type, institution_id, action, game_day, reason) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), humanId, 'COMMUNITY', communityId, 'joined', day, 'voluntary_membership'),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`COMMUNITY-JOINED-${humanId}-${communityId}`, humanId, 'community', 'Community joined', `You joined community ${communityId}.`, communityId),
      ]);
      return Response.json({ ok: true, member: await env.DB.prepare('SELECT * FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId).first(), persistence: 'cloudflare-d1' });
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
      const community = await env.DB.prepare('SELECT id, name, shared_credits FROM communities WHERE id = ?').bind(communityId).first();
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      const entries = await env.DB.prepare("SELECT id, game_day, debit_account, credit_account, amount, reason_id, correlation_id, created_at FROM ledger_entries WHERE reason_type = 'community_contribution' AND credit_account = ? ORDER BY created_at DESC LIMIT 100").bind(communityId).all();
      return Response.json({ community, contributions: entries.results, persistence: 'cloudflare-d1' });
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
      const [community, human, account, membership, prior] = await Promise.all([
        env.DB.prepare('SELECT id, status, shared_credits FROM communities WHERE id = ?').bind(communityId).first<{ id: string; status: string; shared_credits: number }>(),
        env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first(),
        env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(humanId, 'CREDIT').first<{ account_id: string; balance: number }>(),
        env.DB.prepare('SELECT human_id FROM community_members WHERE community_id = ? AND human_id = ?').bind(communityId, humanId).first(),
        env.DB.prepare("SELECT id, amount, game_day FROM ledger_entries WHERE reason_type = 'community_contribution' AND correlation_id = ?").bind(correlationId).first<{ id: string; amount: number; game_day: number }>(),
      ]);
      if (!community) return Response.json({ ok: false, error: 'Community not found' }, { status: 404 });
      if (community.status !== 'active') return Response.json({ ok: false, error: 'Community is not active' }, { status: 409 });
      if (!human || !account) return Response.json({ ok: false, error: 'Contributor account not found' }, { status: 404 });
      if (!membership) return Response.json({ ok: false, error: 'Contributor must be a community member' }, { status: 403 });
      if (prior) return Response.json({ ok: true, alreadyProcessed: true, amount: prior.amount, gameDay: prior.game_day, correlationId, community, persistence: 'cloudflare-d1' });
      if (Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const ledgerId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, account.account_id, amount),
        env.DB.prepare('UPDATE communities SET shared_credits = shared_credits + ? WHERE id = ?').bind(amount, communityId),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(ledgerId, day, account.account_id, communityId, amount, 'CREDIT', 'community_contribution', communityId, 'community-v1', correlationId),
      ]);
      return Response.json({ ok: true, amount, correlationId, community: await env.DB.prepare('SELECT id, name, shared_credits FROM communities WHERE id = ?').bind(communityId).first(), account: await env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE account_id = ?').bind(account.account_id).first(), persistence: 'cloudflare-d1' });
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
      if (!counterpartyId || counterpartyId === viewer.id || !(await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(counterpartyId).first())) return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
      if (title.length < 3 || title.length > 140 || !Number.isFinite(amount) || amount < 0 || amount > 100000 || !Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) return Response.json({ ok: false, error: 'Contract terms are outside engine bounds' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createContractPostgres(repository, { proposerId: viewer.id, kind, counterpartyId, title, terms: body.terms ?? {}, amount, durationDays, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract creation failed' }, { status: 409 });
        }
      }
      const prior = await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE proposer_id = ? AND correlation_id = ?').bind(viewer.id, correlationId).first();
      if (prior) return Response.json({ ok: true, alreadyProcessed: true, contract: prior, correlationId, persistence: 'cloudflare-d1' });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      const contractId = `CON-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      await env.DB.prepare('INSERT INTO negotiated_contracts (id, kind, proposer_id, counterparty_id, title, terms_json, amount, starts_game_day, ends_game_day, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(contractId, kind, viewer.id, counterpartyId, title, JSON.stringify(body.terms ?? {}), amount, day, day + durationDays, correlationId).run();
      await env.DB.batch([
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'contract.proposed', 'A negotiated contract was proposed', JSON.stringify({ contractId, kind, proposer: viewer.id, counterparty: counterpartyId })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), counterpartyId, 'contract', 'Contract proposal received', `${title} was proposed for your acceptance.`, contractId),
      ]);
      return Response.json({ ok: true, contract: await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE id = ?').bind(contractId).first(), correlationId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    const contractActionMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(accept|cancel)$/);
    if (contractActionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = contractActionMatch[2] === 'cancel'
            ? await withRepository(env, (repository) => cancelContractPostgres(repository, contractActionMatch[1], viewer.id))
            : await withRepository(env, (repository) => acceptContractPostgres(repository, contractActionMatch[1], viewer.id));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract action failed' }, { status: 409 });
        }
      }
      const contract = await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE id = ?').bind(contractActionMatch[1]).first<{ id: string; proposer_id: string; counterparty_id: string; amount: number; status: string; title: string }>();
      if (!contract) return Response.json({ ok: false, error: 'Contract not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      if (contractActionMatch[2] === 'cancel') {
        if (contract.proposer_id !== viewer.id && contract.counterparty_id !== viewer.id) return Response.json({ ok: false, error: 'Only a contract party may cancel' }, { status: 403 });
        if (contract.status !== 'proposed') return Response.json({ ok: false, error: 'Only a proposed contract can be cancelled' }, { status: 409 });
        await env.DB.prepare("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = ? AND status = 'proposed'").bind(contract.id).run();
        return Response.json({ ok: true, status: 'cancelled', contractId: contract.id, persistence: 'cloudflare-d1' });
      }
      if (contract.counterparty_id !== viewer.id) return Response.json({ ok: false, error: 'Only the counterparty may accept this contract' }, { status: 403 });
      if (contract.status !== 'proposed') return Response.json({ ok: true, alreadyProcessed: contract.status === 'accepted', status: contract.status, contractId: contract.id, persistence: 'cloudflare-d1' });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => acceptContractPostgres(repository, contract.id, viewer.id));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract settlement failed' }, { status: 409 });
        }
      }
      const payer = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.proposer_id).first<{ account_id: string; balance: number }>();
      const receiver = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.counterparty_id).first<{ account_id: string }>();
      if (!payer || !receiver || Number(payer.balance) < Number(contract.amount)) return Response.json({ ok: false, error: 'Proposer has insufficient Credits to settle this contract' }, { status: 409 });
      const correlationId = `CONTRACT-${contract.id}`;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(contract.amount, payer.account_id, contract.amount),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(contract.amount, receiver.account_id),
        env.DB.prepare("UPDATE negotiated_contracts SET status = 'accepted', accepted_game_day = ? WHERE id = ? AND status = 'proposed'").bind(day, contract.id),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, payer.account_id, receiver.account_id, contract.amount, 'CREDIT', 'contract_payment', contract.id, 'contracts-v1', correlationId),
        env.DB.prepare("UPDATE business_financials SET operating_costs = operating_costs + ?, profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.proposer_id),
        env.DB.prepare("UPDATE business_financials SET revenue = revenue + ?, profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.counterparty_id),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'contract.accepted', 'A negotiated contract was accepted', JSON.stringify({ contractId: contract.id, amount: contract.amount })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), contract.proposer_id, 'contract', 'Contract accepted', `${contract.title} was accepted and ${contract.amount} Credits were settled.`, contract.id),
      ]);
      return Response.json({ ok: true, status: 'accepted', contract: await env.DB.prepare('SELECT * FROM negotiated_contracts WHERE id = ?').bind(contract.id).first(), persistence: 'cloudflare-d1' });
    }
    const contractDisputeMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(dispute|resolve)$/);
    if (contractDisputeMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres' && contractDisputeMatch[2] === 'dispute') {
        const body = await request.json<{ reason?: string }>();
        const reason = body.reason?.trim() ?? '';
        if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => openDisputePostgres(repository, { contractId: contractDisputeMatch[1], claimantId: viewer.id, reason }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyOpen ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Dispute opening failed' }, { status: 409 });
        }
      }
      if (authorityMode(env) === 'postgres' && contractDisputeMatch[2] === 'resolve') {
        const body = await request.json<{ outcome?: string; resolution?: string }>();
        if (!['uphold', 'void'].includes(body.outcome ?? '') || (body.resolution?.trim().length ?? 0) < 10) return Response.json({ ok: false, error: 'A bounded arbitration outcome and resolution are required' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => resolveContractDisputePostgres(repository, { contractId: contractDisputeMatch[1], resolverId: viewer.id, outcome: body.outcome as 'uphold' | 'void', resolution: body.resolution!.trim().slice(0, 1000) }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Arbitration resolution failed' }, { status: 409 });
        }
      }
      const contract = await env.DB.prepare('SELECT id, proposer_id, counterparty_id, amount, status, title FROM negotiated_contracts WHERE id = ?').bind(contractDisputeMatch[1]).first<{ id: string; proposer_id: string; counterparty_id: string; amount: number; status: string; title: string }>();
      if (!contract) return Response.json({ ok: false, error: 'Contract not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 184;
      if (contractDisputeMatch[2] === 'dispute') {
        if (viewer.id !== contract.proposer_id && viewer.id !== contract.counterparty_id) return Response.json({ ok: false, error: 'Only a contract party may open a dispute' }, { status: 403 });
        if (!['accepted', 'completed'].includes(contract.status)) return Response.json({ ok: false, error: 'Only an accepted or completed contract can be disputed' }, { status: 409 });
        const body = await request.json<{ reason?: string }>();
        const reason = body.reason?.trim() ?? '';
        if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
        const existing = await env.DB.prepare("SELECT * FROM contract_disputes WHERE contract_id = ? AND status = 'open'").bind(contract.id).first();
        if (existing) return Response.json({ ok: true, alreadyOpen: true, dispute: existing, persistence: 'cloudflare-d1' });
        const disputeId = `DISPUTE-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
        await env.DB.batch([
          env.DB.prepare('INSERT INTO contract_disputes (id, contract_id, claimant_id, respondent_id, reason) VALUES (?, ?, ?, ?, ?)').bind(disputeId, contract.id, viewer.id, viewer.id === contract.proposer_id ? contract.counterparty_id : contract.proposer_id, reason),
          env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'arbitration.opened', 'A contract dispute was opened', JSON.stringify({ disputeId, contractId: contract.id })),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), contract.proposer_id, 'arbitration', 'Contract dispute opened', `${contract.title} is awaiting OUC arbitration.`, disputeId),
          env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), contract.counterparty_id, 'arbitration', 'Contract dispute opened', `${contract.title} is awaiting OUC arbitration.`, disputeId),
        ]);
        return Response.json({ ok: true, dispute: await env.DB.prepare('SELECT * FROM contract_disputes WHERE id = ?').bind(disputeId).first(), persistence: 'cloudflare-d1' }, { status: 201 });
      }
      if (authorityMode(env) !== 'postgres' && !(await canExerciseDelegatedRole(env, viewer.id, 'OUC-001'))) return Response.json({ ok: false, error: 'OUC arbitration authority is required' }, { status: 403 });
      const body = await request.json<{ outcome?: string; resolution?: string }>();
      if (!['uphold', 'void'].includes(body.outcome ?? '') || (body.resolution?.trim().length ?? 0) < 10) return Response.json({ ok: false, error: 'A bounded arbitration outcome and resolution are required' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => resolveContractDisputePostgres(repository, { contractId: contract.id, resolverId: viewer.id, outcome: body.outcome as 'uphold' | 'void', resolution: body.resolution!.trim().slice(0, 1000) }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Arbitration resolution failed' }, { status: 409 });
        }
      }
      const dispute = await env.DB.prepare("SELECT * FROM contract_disputes WHERE contract_id = ? AND status = 'open'").bind(contract.id).first<{ id: string; claimant_id: string; respondent_id: string }>();
      if (!dispute) return Response.json({ ok: false, error: 'Open dispute not found' }, { status: 404 });
      const statements: D1PreparedStatement[] = [
        env.DB.prepare("UPDATE contract_disputes SET status = 'resolved', outcome = ?, resolved_by = ?, resolved_game_day = ?, resolution = ? WHERE id = ? AND status = 'open'").bind(body.outcome, viewer.id, day, body.resolution!.trim().slice(0, 1000), dispute.id),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'arbitration.resolved', 'A contract dispute was resolved', JSON.stringify({ disputeId: dispute.id, contractId: contract.id, outcome: body.outcome, resolvedBy: viewer.id })),
      ];
      if (body.outcome === 'void') {
        const payer = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.counterparty_id).first<{ account_id: string; balance: number }>();
        const receiver = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(contract.proposer_id).first<{ account_id: string }>();
        if (!payer || !receiver || Number(payer.balance) < Number(contract.amount)) return Response.json({ ok: false, error: 'Counterparty cannot fund the arbitration refund' }, { status: 409 });
        const refundId = `ARBITRATION-REFUND-${contract.id}`;
        statements.push(
          env.DB.prepare("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = ? AND status IN ('accepted','completed')").bind(contract.id),
          env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(contract.amount, payer.account_id, contract.amount),
          env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(contract.amount, receiver.account_id),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(refundId, day, payer.account_id, receiver.account_id, contract.amount, 'CREDIT', 'contract_arbitration_refund', contract.id, 'arbitration-v1', refundId),
          env.DB.prepare("UPDATE business_financials SET operating_costs = MAX(0, operating_costs - ?), profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.proposer_id),
          env.DB.prepare("UPDATE business_financials SET revenue = MAX(0, revenue - ?), profit = profit - ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(contract.amount, contract.amount, day, contract.counterparty_id),
        );
      }
      await env.DB.batch(statements);
      return Response.json({ ok: true, outcome: body.outcome, dispute: await env.DB.prepare('SELECT * FROM contract_disputes WHERE id = ?').bind(dispute.id).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/liquidity' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const liquidity = (await withRepository(env, (repository) => repository.query<{ active_humans: number; money_supply: string; living_cost_index: string }>("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index")))?.rows[0];
        const activeHumans = Number(liquidity?.active_humans ?? 0); const supply = Number(liquidity?.money_supply ?? 0); const livingCostIndex = Number(liquidity?.living_cost_index ?? 1); const target = activeHumans * Math.max(0.5, livingCostIndex) * 100;
        return Response.json({ activeHumans, moneySupply: supply, livingCostIndex, target, corridor: { low: target * 0.8, high: target * 1.2 }, status: supply < target * 0.8 ? 'below-corridor' : supply > target * 1.2 ? 'above-corridor' : 'inside-corridor', persistence: 'planetscale-postgres' });
      }
      const liquidity = await env.DB.prepare("SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index").first<{ active_humans: number; money_supply: number; living_cost_index: number }>();
      const target = Number(liquidity?.active_humans ?? 0) * Math.max(0.5, Number(liquidity?.living_cost_index ?? 1)) * 100;
      const supply = Number(liquidity?.money_supply ?? 0);
      return Response.json({ activeHumans: Number(liquidity?.active_humans ?? 0), moneySupply: supply, livingCostIndex: Number(liquidity?.living_cost_index ?? 1), target, corridor: { low: target * 0.8, high: target * 1.2 }, status: supply < target * 0.8 ? 'below-corridor' : supply > target * 1.2 ? 'above-corridor' : 'inside-corridor', persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/status' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, async (repository) => {
          const [states, events] = await Promise.all([
            repository.query('SELECT * FROM financial_states ORDER BY status DESC, institution_kind, institution_id'),
            repository.query('SELECT * FROM bankruptcy_events ORDER BY game_day DESC, created_at DESC LIMIT 50'),
          ]);
          return { states: states.rows, events: events.rows };
        });
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [states, events] = await Promise.all([
        env.DB.prepare('SELECT * FROM financial_states ORDER BY status DESC, institution_kind, institution_id').all(),
        env.DB.prepare('SELECT * FROM bankruptcy_events ORDER BY game_day DESC, created_at DESC LIMIT 50').all(),
      ]);
      return Response.json({ states: states.results, events: events.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/recover' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ institutionId?: string; amount?: number; otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for financial recovery' }, { status: 401 });
      const institutionId = body.institutionId?.trim() ?? '';
      const amount = Math.round(Number(body.amount) * 100) / 100;
      if (!institutionId || !Number.isFinite(amount) || amount <= 0 || amount > 100000) return Response.json({ ok: false, error: 'Recovery amount must be between 0 and 100,000 Credits' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => recoverInstitutionPostgres(repository, { humanId: viewer.id, institutionId, amount, correlationId: crypto.randomUUID() }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Institution recovery failed';
          return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient|crisis/i.test(message) ? 409 : 400 });
        }
      }
      const institution = await env.DB.prepare('SELECT id, kind FROM institutions WHERE id = ? AND kind IN (\'CITY\', \'CORPORATION\')').bind(institutionId).first<{ id: string; kind: string }>();
      if (!institution) return Response.json({ ok: false, error: 'Recoverable institution not found' }, { status: 404 });
      const eligible = institution.kind === 'CITY'
        ? await hasActiveRole(env, viewer.id, ['ROLE-CITY-MAYOR', 'ROLE-CITY-PLANNER'])
        : await hasActiveRole(env, viewer.id, ['ROLE-CORP-EXECUTIVE', 'ROLE-CORP-TREASURER']);
      if (!eligible) return Response.json({ ok: false, error: 'An active institutional finance role is required' }, { status: 403 });
      const state = await env.DB.prepare("SELECT status FROM financial_states WHERE institution_id = ? AND status IN ('distressed','insolvent')").bind(institutionId).first<{ status: string }>();
      if (!state) return Response.json({ ok: false, error: 'Institution is not currently in a recoverable crisis state' }, { status: 409 });
      const account = await env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = \'CREDIT\'').bind(viewer.id).first<{ account_id: string; balance: number }>();
      if (!account || Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for recovery' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = \'WORLD\'').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = crypto.randomUUID();
      const ledgerId = crypto.randomUUID();
      const targetTable = institution.kind === 'CITY' ? 'cities' : 'corporations';
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, account.account_id, amount),
        env.DB.prepare(`UPDATE ${targetTable} SET treasury = treasury + ? WHERE id = ?`).bind(amount, institutionId),
        env.DB.prepare("UPDATE financial_states SET status = 'active', recovery_game_day = ?, last_reason = 'Player-authorized crisis recovery', updated_at = CURRENT_TIMESTAMP WHERE institution_id = ?").bind(day, institutionId),
        env.DB.prepare('INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason) VALUES (?, ?, ?, ?, \'active\', ?, ?)').bind(crypto.randomUUID(), institutionId, institution.kind, state.status, day, 'Player-authorized crisis recovery'),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'financial_recovery', `${institution.kind} ${institutionId} recovered`, JSON.stringify({ institutionId, amount, humanId: viewer.id })),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(ledgerId, day, account.account_id, institutionId, amount, 'CREDIT', 'institution_recovery', institutionId, 'finance-v2', correlationId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'finance', 'Institution recovered', `${institution.kind} ${institutionId} returned to active status after your ${amount} Credit recovery contribution.`, institutionId),
      ]);
      return Response.json({ ok: true, institutionId, amount, status: 'active', correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/taxes/settle' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ taxableAmount?: number }>();
      const taxableAmount = Number(body.taxableAmount);
      if (!Number.isFinite(taxableAmount) || taxableAmount <= 0) return Response.json({ ok: false, error: 'Taxable amount must be positive' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => settleTaxPostgres(repository, viewer.id, taxableAmount));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Tax settlement failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
        }
      }
      const account = await env.DB.prepare('SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id = ? AND currency = ?').bind(viewer.id, 'CREDIT').first<{ account_id: string; owner_id: string; balance: number }>();
      const accountId = account?.account_id ?? '';
      const [legacyRule, activeFinanceRule] = await Promise.all([
        env.DB.prepare('SELECT * FROM tax_rules WHERE id = ? AND active = 1').bind('TAX-OUC-BASIC').first<{ rate: number; version: number }>(),
        env.DB.prepare("SELECT value_json, version FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'finance' AND status = 'active' ORDER BY version DESC LIMIT 1").first<{ value_json: string; version: number }>(),
      ]);
      if (!legacyRule || !account) return Response.json({ ok: false, error: 'Tax rule or account not found' }, { status: 404 });
      let effectiveRate = Number(legacyRule.rate);
      let effectiveVersion = Number(legacyRule.version);
      if (activeFinanceRule?.value_json) {
        try {
          const configured = JSON.parse(activeFinanceRule.value_json) as { rate?: number };
          if (typeof configured.rate === 'number' && configured.rate >= 0 && configured.rate <= 0.25) {
            effectiveRate = configured.rate;
            effectiveVersion = Number(activeFinanceRule.version);
          }
        } catch (_error) { /* retain the safe legacy rate */ }
      }
      const amount = Math.round(taxableAmount * effectiveRate * 100) / 100;
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = `TAX-${accountId}-${gameDay}-${amount.toFixed(2)}-${effectiveVersion}`;
      const priorSettlement = await env.DB.prepare("SELECT id, amount, game_day, rule_version FROM ledger_entries WHERE reason_type = 'tax_settlement' AND correlation_id = ?").bind(correlationId).first<{ id: string; amount: number; game_day: number; rule_version: string }>();
      if (priorSettlement) return Response.json({ ok: true, alreadySettled: true, amount: priorSettlement.amount, gameDay: priorSettlement.game_day, ruleVersion: priorSettlement.rule_version, correlationId, persistence: 'cloudflare-d1' });
      if (Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for tax settlement' }, { status: 409 });
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(amount, accountId, amount),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(amount, 'account-ouc-treasury'),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, gameDay, accountId, 'account-ouc-treasury', amount, 'CREDIT', 'tax_settlement', accountId, `tax-v${effectiveVersion}`, correlationId),
        env.DB.prepare('INSERT OR IGNORE INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(`TAX-SETTLED-${correlationId}`, viewer.id, 'finance', 'Tax settlement recorded', `${amount} Credits were settled to the OUC treasury at rate ${(effectiveRate * 100).toFixed(2)}% (rule v${effectiveVersion}).`, correlationId),
      ]);
      return Response.json({ ok: true, amount, rate: effectiveRate, ruleVersion: effectiveVersion, correlationId, accounts: (await env.DB.prepare('SELECT * FROM account_balances WHERE account_id IN (?, ?)').bind(accountId, 'account-ouc-treasury').all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance/public-spending' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) !== 'postgres' && !(await hasActiveRole(env, viewer.id, ['ROLE-CITY-MAYOR', 'ROLE-CITY-PLANNER']))) return Response.json({ ok: false, error: 'An active City Mayor or Infrastructure Planner term is required' }, { status: 403 });
      const body = await request.json<{ cityId?: string; category?: string; amount?: number; correlationId?: string }>();
      const cityId = body.cityId || 'CITY-0084';
      const category = body.category?.trim() || 'public-services';
      const amount = Number(body.amount);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Public spending amount must be positive' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => publicSpendingPostgres(repository, { actorId: viewer.id, cityId, category, amount, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Public spending failed';
          return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
        }
      }
      const priorSpending = await env.DB.prepare("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'public_spending' AND correlation_id = ?").bind(correlationId).first<{ amount: number; game_day: number }>();
      if (priorSpending) return Response.json({ ok: true, alreadyProcessed: true, amount: priorSpending.amount, gameDay: priorSpending.game_day, correlationId, persistence: 'cloudflare-d1' });
      const treasury = await env.DB.prepare('SELECT balance FROM account_balances WHERE account_id = ?').bind('account-ouc-treasury').first<{ balance: number }>();
      const city = await env.DB.prepare('SELECT id FROM cities WHERE id = ?').bind(cityId).first();
      if (!city) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      if (!treasury || Number(treasury.balance) < amount) return Response.json({ ok: false, error: 'OUC treasury cannot fund this spending' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ?').bind(amount, 'account-ouc-treasury'),
        env.DB.prepare('UPDATE cities SET treasury = treasury + ? WHERE id = ?').bind(amount, cityId),
        env.DB.prepare('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET amount = amount + excluded.amount, game_day = excluded.game_day').bind(`SPEND-${cityId}-${category}`, cityId, category, amount, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, 'account-ouc-treasury', cityId, amount, 'CREDIT', 'public_spending', cityId, 'finance-v1', correlationId),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'public_spending', `OUC funding reached ${cityId}`, JSON.stringify({ cityId, category, amount, correlationId, actorId: viewer.id })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'finance', 'Public spending recorded', `${amount} Credits were routed from the OUC treasury to ${cityId} for ${category}.`, correlationId),
        env.DB.prepare("INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) SELECT lower(hex(randomblob(16))), human_id, 'finance', 'City funding received', ? || ' Credits were routed to ' || ? || ' for ' || ? || '.', ? FROM memberships WHERE city_id = ? AND human_id != ?").bind(amount, cityId, category, correlationId, cityId, viewer.id),
      ]);
      return Response.json({ ok: true, amount, city: await env.DB.prepare('SELECT * FROM cities WHERE id = ?').bind(cityId).first(), treasury: await env.DB.prepare('SELECT * FROM account_balances WHERE account_id = ?').bind('account-ouc-treasury').first(), correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/book' && request.method === 'GET') {
      const postgresBook = await withRepository(env, async (repository) => {
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
          } catch { /* invalid governance JSON keeps the safe zero fee */ }
        }
        return { book: rows.rows, trades: trades.rows, feeRate };
      });
      if (postgresBook) return Response.json({ ...postgresBook, persistence: 'planetscale-postgres' });
      const rows = await env.DB.prepare("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product").all();
      const trades = await env.DB.prepare('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product').all();
      return Response.json({ book: rows.results, trades: trades.results, feeRate: await marketFeeRate(env), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'GET') {
      const product = url.searchParams.get('product');
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listMarketOrdersPostgres(repository, product));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const query = product ? env.DB.prepare('SELECT * FROM market_orders WHERE product = ? ORDER BY created_at DESC LIMIT 100').bind(product) : env.DB.prepare('SELECT * FROM market_orders ORDER BY created_at DESC LIMIT 100');
      return Response.json({ orders: (await query.all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ humanId?: string; product?: string; quantity?: number; limitPrice?: number; side?: string; correlationId?: string }>();
      const humanId = viewer.id;
      const product = body.product;
      const side = body.side === 'sell' ? 'sell' : 'buy';
      const quantity = Number(body.quantity);
      const limitPrice = Number(body.limitPrice);
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '') || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0) return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => submitMarketOrderPostgres(repository, { humanId, product: product!, side, quantity, limitPrice, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Market order failed';
          const status = /not found/i.test(message) ? 404 : /insufficient|reservation/i.test(message) ? 409 : 400;
          return Response.json({ ok: false, error: message }, { status });
        }
      }
      const priorOrder = await env.DB.prepare('SELECT * FROM market_orders WHERE human_id = ? AND correlation_id = ?').bind(humanId, correlationId).first();
      if (priorOrder) return Response.json({ ok: true, alreadyProcessed: true, order: priorOrder, correlationId, persistence: 'cloudflare-d1' });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first())) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      if (side === 'sell') {
        const inventory = await env.DB.prepare('SELECT amount FROM resource_balances WHERE owner_id = ? AND resource = ?').bind(humanId, product).first<{ amount: number }>();
        if (!inventory || Number(inventory.amount) < quantity) return Response.json({ ok: false, error: `Insufficient ${product} inventory` }, { status: 409 });
      }
      const reservationFeeRate = side === 'buy' ? await marketFeeRate(env) : 0;
      const reservedCredits = side === 'buy' ? Math.round(quantity * limitPrice * (1 + reservationFeeRate) * 100) / 100 : 0;
      const account = side === 'buy' ? await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(humanId).first<{ account_id: string; balance: number }>() : null;
      if (side === 'buy' && (!account || Number(account.balance) < reservedCredits)) return Response.json({ ok: false, error: 'Insufficient Credits to reserve this order' }, { status: 409 });
      const orderId = crypto.randomUUID();
      await env.DB.batch([
        ...(side === 'sell' ? [env.DB.prepare('UPDATE resource_balances SET amount = amount - ? WHERE owner_id = ? AND resource = ? AND amount >= ?').bind(quantity, humanId, product, quantity)] : [env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(reservedCredits, account!.account_id, reservedCredits)]),
        env.DB.prepare('INSERT INTO market_orders (id, human_id, product, side, quantity, limit_price, reserved_credits, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)').bind(orderId, humanId, product, side, quantity, limitPrice, reservedCredits, correlationId),
        env.DB.prepare(`UPDATE market_prices SET ${side === 'sell' ? 'supply' : 'demand'} = ${side === 'sell' ? 'supply' : 'demand'} + ? WHERE product = ?`).bind(quantity, product),
      ]);
      const coordinator = env.MARKET_COORDINATOR.getByName(`market-${product}`);
      const coordination = await coordinator.submitCommand({ type: 'order.submitted', orderId, product, quantity });
      return Response.json({ ok: true, order: await env.DB.prepare('SELECT * FROM market_orders WHERE id = ?').bind(orderId).first(), coordination, correlationId, persistence: 'cloudflare-d1' });
    }
    const cancelOrderMatch = url.pathname.match(/^\/api\/market\/orders\/([^/]+)$/);
    if (cancelOrderMatch && request.method === 'DELETE') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => cancelMarketOrderPostgres(repository, { orderId: cancelOrderMatch[1], humanId: viewer.id }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market order cancellation failed' }, { status: 404 });
        }
      }
      const order = await env.DB.prepare("SELECT * FROM market_orders WHERE id = ? AND human_id = ? AND status IN ('open','partial')").bind(cancelOrderMatch[1], viewer.id).first<Record<string, unknown>>();
      if (!order) return Response.json({ ok: false, error: 'Open order not found for this Human' }, { status: 404 });
      const remaining = Number(order.quantity) - Number(order.filled_quantity);
      const release = String(order.side) === 'sell'
        ? env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(viewer.id, order.product, remaining)
        : env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(Number(order.reserved_credits ?? 0), viewer.id);
      const signal = String(order.side) === 'sell' ? 'supply' : 'demand';
      await env.DB.batch([
        release,
        env.DB.prepare("UPDATE market_orders SET status = 'cancelled', reserved_credits = 0 WHERE id = ? AND human_id = ?").bind(order.id, viewer.id),
        env.DB.prepare(`UPDATE market_prices SET ${signal} = MAX(0, ${signal} - ?) WHERE product = ?`).bind(remaining, order.product),
      ]);
      return Response.json({ ok: true, orderId: order.id, released: remaining, side: order.side, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/settle' && request.method === 'POST') {
      const body = await request.json<{ product?: string }>();
      const product = body.product;
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '')) return Response.json({ ok: false, error: 'Unknown product' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => settleMarketPostgres(repository, product!));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market settlement failed' }, { status: 409 });
        }
      }
      const price = await env.DB.prepare('SELECT * FROM market_prices WHERE product = ?').bind(product).first<{ price: number; supply: number }>();
      const orderOrder = (await marketFairAllocation(env)) ? 'filled_quantity ASC, created_at ASC' : 'created_at ASC';
      const buy = await env.DB.prepare(`SELECT * FROM market_orders WHERE product = ? AND side = 'buy' AND status IN ('open','partial') AND limit_price >= ? ORDER BY ${orderOrder} LIMIT 1`).bind(product, price?.price ?? 0).first<Record<string, unknown>>();
      const sell = await env.DB.prepare(`SELECT * FROM market_orders WHERE product = ? AND side = 'sell' AND status IN ('open','partial') AND limit_price <= ? ORDER BY ${orderOrder} LIMIT 1`).bind(product, price?.price ?? 0).first<Record<string, unknown>>();
      if (!price || !buy || !sell || String(buy.human_id) === String(sell.human_id)) return Response.json({ ok: true, filled: false, reason: 'No eligible matched orders or price', persistence: 'cloudflare-d1' });
      const remaining = Math.min(Number(buy.quantity) - Number(buy.filled_quantity), Number(sell.quantity) - Number(sell.filled_quantity));
      const fill = Math.min(remaining, Number(price.supply));
      if (fill <= 0) return Response.json({ ok: true, filled: false, reason: 'No available supply', persistence: 'cloudflare-d1' });
      const account = await env.DB.prepare('SELECT account_id, balance FROM account_balances WHERE owner_id = ?').bind(buy.human_id).first<{ account_id: string; balance: number }>();
      const total = Math.round(fill * Number(price.price) * 100) / 100;
      const feeRate = await marketFeeRate(env);
      const fee = Math.round(total * feeRate * 100) / 100;
      const payable = total + fee;
      const reserved = Number(buy.reserved_credits ?? 0);
      if (!account || (reserved <= 0 && Number(account.balance) < payable)) {
        await env.DB.prepare("UPDATE market_orders SET status = 'rejected' WHERE id = ?").bind(buy.id).run();
        return Response.json({ ok: false, error: 'Insufficient Credits', orderId: buy.id }, { status: 409 });
      }
      const reservationUsed = reserved > 0 ? Math.round(fill * Number(buy.limit_price) * (1 + feeRate) * 100) / 100 : payable;
      const reservationRefund = Math.max(0, Math.round((reservationUsed - payable) * 100) / 100);
      if (reserved > 0 && reserved < reservationUsed) return Response.json({ ok: false, error: 'Buy order reservation is inconsistent', orderId: buy.id }, { status: 409 });
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const tradeId = crypto.randomUUID();
      const newBuyFilled = Number(buy.filled_quantity) + fill;
      const newSellFilled = Number(sell.filled_quantity) + fill;
      const buyStatus = newBuyFilled >= Number(buy.quantity) ? 'filled' : 'partial';
      const sellStatus = newSellFilled >= Number(sell.quantity) ? 'filled' : 'partial';
      await env.DB.batch([
        ...(reserved > 0 ? [env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(reservationRefund, buy.human_id)] : [env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE owner_id = ? AND balance >= ?').bind(payable, buy.human_id, payable)]),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(fee, 'account-ouc-treasury'),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE owner_id = ?').bind(total, sell.human_id),
        env.DB.prepare("UPDATE business_financials SET revenue = revenue + ?, profit = profit + ?, last_game_day = ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = ? AND status = 'active' ORDER BY id LIMIT 1)").bind(total, total, gameDay, sell.human_id),
        env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(buy.human_id, product, fill),
        env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, reserved_credits = MAX(0, reserved_credits - ?), status = ? WHERE id = ?').bind(newBuyFilled, reservationUsed, buyStatus, buy.id),
        env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, status = ? WHERE id = ?').bind(newSellFilled, sellStatus, sell.id),
        env.DB.prepare('UPDATE market_prices SET supply = supply - ?, demand = MAX(0, demand - ?), game_day = ? WHERE product = ?').bind(fill, fill, gameDay, product),
        env.DB.prepare('INSERT INTO market_trades (id, order_id, product, quantity, clearing_price, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(tradeId, buy.id, product, fill, price.price, gameDay),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), String(buy.human_id), 'market', 'Market purchase filled', `${fill} ${product} acquired at ${price.price} Credits.`, tradeId),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), String(sell.human_id), 'market', 'Market sale filled', `${fill} ${product} sold at ${price.price} Credits.`, tradeId),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(tradeId, gameDay, buy.human_id, sell.human_id, total, 'CREDIT', 'market_trade', buy.id, 'market-v2', tradeId),
        ...(fee > 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), gameDay, buy.human_id, 'account-ouc-treasury', fee, 'CREDIT', 'market_fee', buy.id, 'market-v2', tradeId)] : []),
      ]);
      return Response.json({ ok: true, filled: true, buyOrderId: buy.id, sellOrderId: sell.id, tradeId, product, quantity: fill, clearingPrice: price.price, total, fee, payable, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        await withRepository(env, (repository) => resolveProposalsPostgres(repository));
        const result = await withRepository(env, (repository) => listGovernanceProposalsPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      await resolveGovernanceProposals(env);
      const proposals = await env.DB.prepare('SELECT * FROM proposals ORDER BY closes_at ASC').all();
      const ballots = await env.DB.prepare('SELECT proposal_id, choice, ROUND(SUM(weight), 3) AS count FROM ballots GROUP BY proposal_id, choice').all();
      return Response.json({ proposals: proposals.results, voteCounts: ballots.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/rules' && request.method === 'GET') {
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => listGovernanceRulesPostgres(repository));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const rules = await env.DB.prepare("SELECT * FROM governance_rules WHERE status IN ('active','superseded') ORDER BY institution_id, category, version DESC").all();
      return Response.json({ rules: rules.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'POST') {
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ institutionId?: string; title?: string; body?: string; durationHours?: number; ruleVersionId?: string; target?: { category?: string; value?: Record<string, unknown> }; correlationId?: string }>();
      const institutionId = body.institutionId?.trim() || 'OUC-001';
      const title = body.title?.trim();
      const proposalBody = body.body?.trim();
      const durationHours = Number(body.durationHours ?? 72);
      if (!title || title.length < 8 || title.length > 140) return Response.json({ ok: false, error: 'Proposal title must be 8–140 characters' }, { status: 400 });
      if (!proposalBody || proposalBody.length < 20 || proposalBody.length > 4000) return Response.json({ ok: false, error: 'Proposal body must be 20–4000 characters' }, { status: 400 });
      if (!Number.isInteger(durationHours) || durationHours < 24 || durationHours > 168) return Response.json({ ok: false, error: 'Decision window must be between 24 and 168 hours' }, { status: 400 });
      const correlationId = body.correlationId?.trim() || crypto.randomUUID();
      if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        const targetCategory = body.target?.category?.trim() || null;
        const targetValue = body.target?.value ?? null;
        if (targetCategory && !['market', 'finance', 'services', 'technology'].includes(targetCategory)) return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => createProposalPostgres(repository, { humanId: human.id, institutionId, title, body: proposalBody, durationHours, ruleVersionId: body.ruleVersionId, targetCategory, targetValue, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Proposal creation failed' }, { status: 409 });
        }
      }
      const priorProposal = await env.DB.prepare('SELECT * FROM proposals WHERE institution_id = ? AND correlation_id = ?').bind(institutionId, correlationId).first();
      if (priorProposal) return Response.json({ ok: true, alreadyProcessed: true, proposal: priorProposal, correlationId, persistence: 'cloudflare-d1' });
      const institution = await env.DB.prepare("SELECT id, kind, status FROM institutions WHERE id = ? AND kind IN ('OUC','CITY','CORPORATION')").bind(institutionId).first<{ id: string; kind: string; status: string }>();
      if (!institution) return Response.json({ ok: false, error: 'Governable institution not found' }, { status: 404 });
      if (institution.status !== 'active') return Response.json({ ok: false, error: 'Institution is not active' }, { status: 409 });
      if (!(await eligibleForInstitution(env, human.id, institutionId))) return Response.json({ ok: false, error: 'Human is not eligible to propose at this institution' }, { status: 403 });
      const rule = body.ruleVersionId
        ? await env.DB.prepare("SELECT id, status, value_json FROM governance_rules WHERE id = ? AND institution_id = ?").bind(body.ruleVersionId, institutionId).first<{ id: string; status: string; value_json: string }>()
        : await env.DB.prepare("SELECT id, status, value_json FROM governance_rules WHERE institution_id = ? AND status = 'active' ORDER BY version DESC LIMIT 1").bind(institutionId).first<{ id: string; status: string; value_json: string }>();
      if (!rule || rule.status !== 'active') return Response.json({ ok: false, error: 'An active governance rule version is required' }, { status: 409 });
      const proposalId = `P-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      let ruleConfig: Record<string, unknown> = {};
      try { ruleConfig = JSON.parse(rule.value_json ?? '{}') as Record<string, unknown>; } catch (_error) { /* use engine defaults */ }
      const quorum = Number(ruleConfig.quorum ?? 0.25);
      const approvalThreshold = Number(ruleConfig.approvalThreshold ?? 0.5);
      const implementationDelay = Number(ruleConfig.implementationDelayDays ?? 1);
      if (!(quorum > 0 && quorum <= 1) || !(approvalThreshold > 0 && approvalThreshold <= 1) || !Number.isInteger(implementationDelay) || implementationDelay < 0 || implementationDelay > 30) return Response.json({ ok: false, error: 'Governance rule parameters are invalid' }, { status: 409 });
      const targetCategory = body.target?.category?.trim() || null;
      const targetValue = body.target?.value ? JSON.stringify(body.target.value) : null;
      if (targetCategory && !['market', 'finance', 'services', 'technology'].includes(targetCategory)) return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
      if (targetValue && targetValue.length > 2000) return Response.json({ ok: false, error: 'Target rule payload is too large' }, { status: 400 });
      await env.DB.prepare("INSERT INTO proposals (id, institution_id, title, body, status, opens_at, closes_at, rule_version_id, quorum, approval_threshold, implementation_delay_days, implementation_at, target_category, target_value_json, correlation_id) VALUES (?, ?, ?, ?, 'open', CURRENT_TIMESTAMP, datetime('now', ?), ?, ?, ?, ?, datetime('now', ?), ?, ?, ?)").bind(proposalId, institutionId, title, proposalBody, `+${durationHours} hours`, rule.id, quorum, approvalThreshold, implementationDelay, `+${durationHours + implementationDelay * 24} hours`, targetCategory, targetValue, correlationId).run();
      return Response.json({ ok: true, proposal: await env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind(proposalId).first(), createdBy: human.id, correlationId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    const voteMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/vote$/);
    if (voteMatch && request.method === 'POST') {
      const proposalId = voteMatch[1];
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ vote?: string }>();
        const human = await currentHuman(request, env);
        if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
        if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => castVotePostgres(repository, { proposalId, humanId: human.id, choice: body.vote! }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Ballot failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('already') ? 409 : 403 });
        }
      }
      await resolveGovernanceProposals(env);
      const body = await request.json<{ vote?: string }>();
      const human = await currentHuman(request, env);
      if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const humanId = human.id;
      if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
      if (!(await env.DB.prepare('SELECT id FROM proposals WHERE id = ? AND status = ?').bind(proposalId, 'open').first())) return Response.json({ ok: false, error: 'Open proposal not found' }, { status: 404 });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first())) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const proposal = await env.DB.prepare('SELECT institution_id FROM proposals WHERE id = ?').bind(proposalId).first<{ institution_id: string }>();
      if (!(await canExerciseDelegatedRole(env, humanId, proposal?.institution_id ?? ''))) return Response.json({ ok: false, error: 'Human is not eligible to vote at this institution' }, { status: 403 });
      const weight = await votingWeight(env, humanId, proposal?.institution_id ?? '');
      try {
        await env.DB.prepare('INSERT INTO ballots (proposal_id, human_id, choice, weight) VALUES (?, ?, ?, ?)').bind(proposalId, humanId, body.vote, weight).run();
      } catch (_error) {
        return Response.json({ ok: false, error: 'Ballot already recorded' }, { status: 409 });
      }
      const counts = await env.DB.prepare('SELECT choice, ROUND(SUM(weight), 3) AS count FROM ballots WHERE proposal_id = ? GROUP BY choice').bind(proposalId).all();
      return Response.json({ ok: true, proposalId, humanId, vote: body.vote, weight, counts: counts.results, persistence: 'cloudflare-d1' });
    }
    const executeProposalMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/execute$/);
    if (executeProposalMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => executeProposalPostgres(repository, { proposalId: executeProposalMatch[1], humanId: viewer.id }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Proposal execution failed' }, { status: 409 });
        }
      }
      const proposal = await env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind(executeProposalMatch[1]).first<Record<string, unknown>>();
      if (!proposal) return Response.json({ ok: false, error: 'Proposal not found' }, { status: 404 });
      if (proposal.outcome !== 'passed') return Response.json({ ok: false, error: 'Only passed proposals can be executed' }, { status: 409 });
      if (proposal.executed_at) return Response.json({ ok: true, executionStatus: 'executed', proposal, persistence: 'cloudflare-d1' });
      if (new Date(String(proposal.implementation_at ?? '')).getTime() > Date.now()) return Response.json({ ok: false, error: 'Implementation delay has not elapsed' }, { status: 409 });
      if (!(await canExerciseDelegatedRole(env, viewer.id, String(proposal.institution_id)))) return Response.json({ ok: false, error: 'Human is not authorized to execute this institution rule' }, { status: 403 });
      const category = String(proposal.target_category ?? '').trim();
      const valueJson = String(proposal.target_value_json ?? '');
      if (!category || !valueJson) {
        await env.DB.prepare("UPDATE proposals SET executed_at = CURRENT_TIMESTAMP, execution_status = 'skipped' WHERE id = ?").bind(proposal.id).run();
        return Response.json({ ok: true, executionStatus: 'skipped', reason: 'Proposal has no target rule payload', persistence: 'cloudflare-d1' });
      }
      if (!['market', 'finance', 'services', 'technology'].includes(category) || valueJson.length > 2000) return Response.json({ ok: false, error: 'Target rule is outside engine bounds' }, { status: 409 });
      let targetValue: Record<string, unknown>;
      try { targetValue = JSON.parse(valueJson) as Record<string, unknown>; } catch (_error) { return Response.json({ ok: false, error: 'Target rule payload is invalid JSON' }, { status: 409 }); }
      if (category === 'finance' && targetValue.rate !== undefined && (!(typeof targetValue.rate === 'number') || Number(targetValue.rate) < 0 || Number(targetValue.rate) > 0.25)) return Response.json({ ok: false, error: 'Finance rule rate must be between 0 and 0.25' }, { status: 409 });
      const prior = await env.DB.prepare("SELECT version FROM governance_rules WHERE institution_id = ? AND category = ? ORDER BY version DESC LIMIT 1").bind(proposal.institution_id, category).first<{ version: number }>();
      const ruleId = `RULE-${String(proposal.institution_id)}-${category}-${Number(prior?.version ?? 0) + 1}`;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO governance_rules (id, institution_id, name, category, value_json, version, status, created_by) VALUES (?, ?, ?, ?, ?, ?, 'active', ?)").bind(ruleId, proposal.institution_id, String(proposal.title), category, JSON.stringify(targetValue), Number(prior?.version ?? 0) + 1, viewer.id),
        env.DB.prepare("UPDATE governance_rules SET status = 'superseded' WHERE institution_id = ? AND category = ? AND status = 'active'").bind(proposal.institution_id, category),
        env.DB.prepare("UPDATE proposals SET executed_at = CURRENT_TIMESTAMP, execution_status = 'executed' WHERE id = ?").bind(proposal.id),
          env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, (SELECT game_day FROM world_state WHERE id = \'WORLD\'), ?, ?, ?)').bind(crypto.randomUUID(), 'rule.changed', `Rule ${category} changed`, JSON.stringify({ proposalId: proposal.id, ruleId })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'governance', 'Rule executed', `Your institution executed ${category}.`, ruleId),
      ]);
      return Response.json({ ok: true, executionStatus: 'executed', rule: await env.DB.prepare('SELECT * FROM governance_rules WHERE id = ?').bind(ruleId).first(), persistence: 'cloudflare-d1' });
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
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => createBusinessPostgres(repository, { ownerId: viewer.id, name, sector, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Business registration failed';
          return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /requires/i.test(message) ? 409 : 400 });
        }
      }
      const priorRegistration = await env.DB.prepare("SELECT reason_id FROM ledger_entries WHERE reason_type = 'business_registration' AND correlation_id = ?").bind(correlationId).first<{ reason_id: string }>();
      if (priorRegistration) return Response.json({ ok: true, alreadyProcessed: true, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(priorRegistration.reason_id).first(), shares: 100, correlationId, persistence: 'cloudflare-d1' });
      if (await env.DB.prepare('SELECT id FROM institutions WHERE name = ?').bind(name).first()) return Response.json({ ok: false, error: 'Business name already exists' }, { status: 409 });
      const account = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>();
      const fee = 250;
      if (!account || Number(account.balance) < fee) return Response.json({ ok: false, error: 'Business registration requires 250 Credits' }, { status: 409 });
      const businessId = `B-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(fee, account.account_id, fee),
        env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE account_id = 'account-ouc-treasury'").bind(fee),
        env.DB.prepare("INSERT INTO institutions (id, kind, name, status) VALUES (?, 'BUSINESS', ?, 'active')").bind(businessId, name),
        env.DB.prepare('INSERT INTO businesses (id, owner_id, name, policy, condition, sector) VALUES (?, ?, ?, \'reliability\', 100, ?)').bind(businessId, viewer.id, name, sector),
        env.DB.prepare('INSERT INTO business_financials (business_id, last_game_day) VALUES (?, ?)').bind(businessId, day),
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, 100)').bind(businessId, viewer.id),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, account.account_id, 'account-ouc-treasury', fee, 'CREDIT', 'business_registration', businessId, 'business-v1', correlationId),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.formed', `${name} was registered`, JSON.stringify({ businessId, sector, founder: viewer.id })),
      ]);
      return Response.json({ ok: true, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(businessId).first(), shares: 100, fee, correlationId, persistence: 'cloudflare-d1' }, { status: 201 });
    }
    if ((url.pathname === '/api/businesses/kline-works/policy' || url.pathname === '/api/businesses/me/policy') && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ policy?: string }>();
      if (!['reliability', 'margin', 'capacity'].includes(body.policy ?? '')) return Response.json({ ok: false, error: 'Unknown business policy' }, { status: 400 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => setBusinessPolicyPostgres(repository, { humanId: viewer.id, policy: body.policy! }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business policy update failed' }, { status: 404 }); }
      }
      const business = await env.DB.prepare("SELECT businesses.id FROM businesses LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.owner_id = ? OR business_management.manager_id = ? ORDER BY businesses.id LIMIT 1").bind(viewer.id, viewer.id).first<{ id: string }>();
      if (!business) return Response.json({ ok: false, error: 'No managed business is available to this Human' }, { status: 404 });
      await env.DB.prepare('UPDATE businesses SET policy = ? WHERE id = ?').bind(body.policy, business.id).run();
      return Response.json({ ok: true, policy: body.policy, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(business.id).first(), persistence: 'cloudflare-d1' });
    }
    const managerMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/manager$/);
    if (managerMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ managerId?: string }>();
        try {
          const result = await withRepository(env, (repository) => appointManagerPostgres(repository, { ownerId: viewer.id, businessId: managerMatch[1], managerId: body.managerId?.trim() ?? '' }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Manager appointment failed' }, { status: 403 }); }
      }
      const business = await env.DB.prepare('SELECT id, owner_id FROM businesses WHERE id = ?').bind(managerMatch[1]).first<{ id: string; owner_id: string }>();
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      if (business.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the Business owner may appoint its manager' }, { status: 403 });
      const body = await request.json<{ managerId?: string }>();
      const managerId = body.managerId?.trim() ?? '';
      const manager = await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(managerId).first();
      if (!manager) return Response.json({ ok: false, error: 'Active manager Human not found' }, { status: 404 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 0;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO business_management (business_id, manager_id, appointed_by, appointed_game_day) VALUES (?, ?, ?, ?) ON CONFLICT(business_id) DO UPDATE SET manager_id = excluded.manager_id, appointed_by = excluded.appointed_by, appointed_game_day = excluded.appointed_game_day, updated_at = CURRENT_TIMESTAMP').bind(business.id, managerId, viewer.id, day),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.manager_appointed', `Manager appointed for ${business.id}`, JSON.stringify({ businessId: business.id, managerId, appointedBy: viewer.id })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), managerId, 'governance', 'Business management appointment', `You were appointed manager of ${business.id}.`, business.id),
      ]);
      return Response.json({ ok: true, management: await env.DB.prepare('SELECT * FROM business_management WHERE business_id = ?').bind(business.id).first(), persistence: 'cloudflare-d1' });
    }
    const ownershipRegistryMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/ownership$/);
    if (ownershipRegistryMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        try {
          const result = await withRepository(env, (repository) => ownershipRegistryPostgres(repository, ownershipRegistryMatch[1]));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business not found' }, { status: 404 }); }
      }
      const business = await env.DB.prepare('SELECT id, name, owner_id FROM businesses WHERE id = ?').bind(ownershipRegistryMatch[1]).first<{ id: string; name: string; owner_id: string }>();
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      const holders = await env.DB.prepare('SELECT business_shares.holder_id, humans.display_name, business_shares.shares FROM business_shares JOIN humans ON humans.id = business_shares.holder_id WHERE business_shares.business_id = ? ORDER BY business_shares.shares DESC, business_shares.holder_id').bind(business.id).all<{ holder_id: string; display_name: string; shares: number }>();
      const total = holders.results.reduce((sum, holder) => sum + Number(holder.shares), 0);
      const registry = holders.results.map((holder) => ({ ...holder, percentage: total > 0 ? Math.round(Number(holder.shares) / total * 10000) / 100 : 0 }));
      return Response.json({ business, totalIssuedShares: total, controllingHumanId: registry[0]?.holder_id ?? null, holders: registry, ownershipAndManagementAreSeparate: true, persistence: 'cloudflare-d1' });
    }
    const financialsMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/financials$/);
    if (financialsMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => readBusinessPostgres(repository, financialsMatch[1], viewer.id));
        if (result?.business) return Response.json({ ...result, accounting: { revenue: 'market-cleared sales and accepted contract income', operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax', profit: 'revenue minus operating costs' }, persistence: 'planetscale-postgres' });
        return Response.json({ ok: false, error: result?.error ?? 'Business financial statement is not available to this Human' }, { status: 403 });
      }
      const business = await env.DB.prepare("SELECT businesses.id, businesses.name, businesses.owner_id, businesses.status, business_financials.revenue, business_financials.operating_costs, business_financials.profit, business_financials.taxed_revenue, business_financials.last_game_day, business_financials.updated_at FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = ? AND (businesses.owner_id = ? OR business_management.manager_id = ? OR EXISTS (SELECT 1 FROM business_shares WHERE business_shares.business_id = businesses.id AND business_shares.holder_id = ?))").bind(financialsMatch[1], viewer.id, viewer.id, viewer.id).first();
      if (!business) return Response.json({ ok: false, error: 'Business financial statement is not available to this Human' }, { status: 403 });
      return Response.json({ business, accounting: { revenue: 'market-cleared sales and accepted contract income', operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax', profit: 'revenue minus operating costs' }, persistence: 'cloudflare-d1' });
    }
    const constitutionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/constitution$/);
    if (constitutionMatch && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => repository.query('SELECT business_constitutions.*, businesses.name, businesses.owner_id FROM business_constitutions JOIN businesses ON businesses.id = business_constitutions.business_id WHERE business_constitutions.business_id = $1', [constitutionMatch[1]]));
        if (result?.rows[0]) return Response.json({ constitution: result.rows[0], management: { ownerId: result.rows[0].owner_id, ownershipAndManagementAreSeparate: true }, persistence: 'planetscale-postgres' });
        return Response.json({ ok: false, error: 'Business constitution not found' }, { status: 404 });
      }
      const constitution = await env.DB.prepare('SELECT business_constitutions.*, businesses.name, businesses.owner_id FROM business_constitutions JOIN businesses ON businesses.id = business_constitutions.business_id WHERE business_constitutions.business_id = ?').bind(constitutionMatch[1]).first<Record<string, unknown>>();
      if (!constitution) return Response.json({ ok: false, error: 'Business constitution not found' }, { status: 404 });
      return Response.json({ constitution, management: { ownerId: constitution.owner_id, ownershipAndManagementAreSeparate: true }, persistence: 'cloudflare-d1' });
    }
    if (constitutionMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const body = await request.json<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>();
        const shareholderVoteThreshold = Number(body.shareholderVoteThreshold); const boardApprovalThreshold = Number(body.boardApprovalThreshold); const dilutionNoticeDays = Number(body.dilutionNoticeDays);
        if (!(shareholderVoteThreshold > 0 && shareholderVoteThreshold <= 1) || !(boardApprovalThreshold > 0 && boardApprovalThreshold <= 1) || !Number.isInteger(dilutionNoticeDays) || dilutionNoticeDays < 0 || dilutionNoticeDays > 30) return Response.json({ ok: false, error: 'Constitution thresholds or notice period are invalid' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => updateConstitutionPostgres(repository, { ownerId: viewer.id, businessId: constitutionMatch[1], shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Constitution update failed' }, { status: 403 }); }
      }
      const business = await env.DB.prepare('SELECT id, owner_id FROM businesses WHERE id = ?').bind(constitutionMatch[1]).first<{ id: string; owner_id: string }>();
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      if (business.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the Business owner may update its constitution' }, { status: 403 });
      const body = await request.json<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>();
      const shareholderVoteThreshold = Number(body.shareholderVoteThreshold);
      const boardApprovalThreshold = Number(body.boardApprovalThreshold);
      const dilutionNoticeDays = Number(body.dilutionNoticeDays);
      if (!(shareholderVoteThreshold > 0 && shareholderVoteThreshold <= 1) || !(boardApprovalThreshold > 0 && boardApprovalThreshold <= 1) || !Number.isInteger(dilutionNoticeDays) || dilutionNoticeDays < 0 || dilutionNoticeDays > 30) return Response.json({ ok: false, error: 'Constitution thresholds or notice period are invalid' }, { status: 400 });
      const day = (await env.DB.prepare("SELECT game_day FROM world_state WHERE id = 'WORLD'").first<{ game_day: number }>())?.game_day ?? 0;
      const current = await env.DB.prepare('SELECT version FROM business_constitutions WHERE business_id = ?').bind(business.id).first<{ version: number }>();
      const version = Number(current?.version ?? 0) + 1;
      await env.DB.batch([
        env.DB.prepare('INSERT INTO business_constitutions (business_id, version, shareholder_vote_threshold, board_approval_threshold, dilution_notice_days, updated_by, updated_game_day) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(business_id) DO UPDATE SET version = excluded.version, shareholder_vote_threshold = excluded.shareholder_vote_threshold, board_approval_threshold = excluded.board_approval_threshold, dilution_notice_days = excluded.dilution_notice_days, updated_by = excluded.updated_by, updated_game_day = excluded.updated_game_day, updated_at = CURRENT_TIMESTAMP').bind(business.id, version, shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays, viewer.id, day),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.constitution_changed', `Business Constitution updated for ${business.id}`, JSON.stringify({ businessId: business.id, version, shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays, updatedBy: viewer.id })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'governance', 'Business Constitution updated', `${business.id} now operates under Constitution version ${version}.`, business.id),
      ]);
      return Response.json({ ok: true, constitution: await env.DB.prepare('SELECT * FROM business_constitutions WHERE business_id = ?').bind(business.id).first(), persistence: 'cloudflare-d1' });
    }
    const shareTransferMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/transfer$/);
    if (shareTransferMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ recipientId?: string; shares?: number; otp?: string; correlationId?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for ownership transfers' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const recipientId = body.recipientId?.trim() ?? '';
        const shares = Number(body.shares);
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares <= 0 || correlationId.length > 160) return Response.json({ ok: false, error: 'A valid recipient, positive whole-share amount, and correlation ID are required' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => transferSharesPostgres(repository, { holderId: viewer.id, businessId: shareTransferMatch[1] === 'me' ? null : shareTransferMatch[1], recipientId, shares, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share transfer failed' }, { status: 409 });
        }
      }
      const businessId = shareTransferMatch[1] === 'me'
        ? (await env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ? ORDER BY id LIMIT 1').bind(viewer.id).first<{ id: string }>())?.id
        : shareTransferMatch[1];
      const recipientId = body.recipientId?.trim();
      const shares = Number(body.shares);
      if (!businessId || !recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares <= 0) return Response.json({ ok: false, error: 'A valid recipient and positive whole-share amount are required' }, { status: 400 });
      const [business, recipient, holding] = await Promise.all([
        env.DB.prepare('SELECT id FROM businesses WHERE id = ?').bind(businessId).first(),
        env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(recipientId).first(),
        env.DB.prepare('SELECT shares FROM business_shares WHERE business_id = ? AND holder_id = ?').bind(businessId, viewer.id).first<{ shares: number }>(),
      ]);
      if (!business) return Response.json({ ok: false, error: 'Business not found' }, { status: 404 });
      if (!recipient) return Response.json({ ok: false, error: 'Recipient Human not found' }, { status: 404 });
      if (!holding || Number(holding.shares) < shares) return Response.json({ ok: false, error: 'Insufficient shares' }, { status: 409 });
      const transferDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const senderUpdate = Number(holding.shares) === shares
        ? env.DB.prepare('DELETE FROM business_shares WHERE business_id = ? AND holder_id = ?').bind(businessId, viewer.id)
        : env.DB.prepare('UPDATE business_shares SET shares = shares - ?, updated_at = CURRENT_TIMESTAMP WHERE business_id = ? AND holder_id = ?').bind(shares, businessId, viewer.id);
      await env.DB.batch([
        senderUpdate,
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, ?) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = shares + excluded.shares, updated_at = CURRENT_TIMESTAMP').bind(businessId, recipientId, shares),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', businessId, viewer.id, recipientId, shares, 'share_transfer', businessId, transferDay),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'ownership', 'Business shares transferred', `${shares} shares in ${businessId} were transferred to ${recipientId}.`, businessId, crypto.randomUUID(), recipientId, 'ownership', 'Business shares received', `${shares} shares in ${businessId} were transferred to you by ${viewer.id}.`, businessId),
      ]);
      return Response.json({ ok: true, businessId, from: viewer.id, to: recipientId, shares, holdings: (await env.DB.prepare('SELECT holder_id, shares FROM business_shares WHERE business_id = ? ORDER BY shares DESC').bind(businessId).all()).results, persistence: 'cloudflare-d1' });
    }
    const shareIssueMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/issue$/);
    if (shareIssueMatch && request.method === 'POST') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      const body = await request.json<{ recipientId?: string; shares?: number; pricePerShare?: number; otp?: string; correlationId?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for share issuance' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const recipientId = body.recipientId?.trim() ?? '';
        const shares = Number(body.shares);
        const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
        const correlationId = body.correlationId?.trim() || crypto.randomUUID();
        if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000 || correlationId.length > 160) return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
        try {
          const result = await withRepository(env, (repository) => issueSharesPostgres(repository, { ownerId: viewer.id, businessId: shareIssueMatch[1], recipientId, shares, pricePerShare, correlationId }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share issuance failed' }, { status: 409 });
        }
      }
      const business = await env.DB.prepare('SELECT id, owner_id FROM businesses WHERE id = ?').bind(shareIssueMatch[1]).first<{ id: string; owner_id: string }>();
      const recipientId = body.recipientId?.trim();
      const shares = Number(body.shares);
      const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
      if (!business || business.owner_id !== viewer.id) return Response.json({ ok: false, error: 'Only the Business owner may issue shares' }, { status: 403 });
      if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000) return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
      const recipient = await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(recipientId).first();
      if (!recipient) return Response.json({ ok: false, error: 'Recipient Human not found' }, { status: 404 });
      const buyerAccount = await env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(recipientId).first<{ account_id: string; balance: number }>();
      const total = Math.round(shares * pricePerShare * 100) / 100;
      if (!buyerAccount || Number(buyerAccount.balance) < total) return Response.json({ ok: false, error: 'Recipient has insufficient Credits' }, { status: 409 });
      const ownerAccount = await env.DB.prepare("SELECT account_id FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string }>();
      if (!ownerAccount) return Response.json({ ok: false, error: 'Owner account not found' }, { status: 404 });
      const existingHolders = (await env.DB.prepare('SELECT holder_id FROM business_shares WHERE business_id = ? AND holder_id != ?').bind(business.id, recipientId).all<{ holder_id: string }>()).results;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ? AND balance >= ?').bind(total, buyerAccount.account_id, total),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(total, ownerAccount.account_id),
        env.DB.prepare('INSERT INTO business_shares (business_id, holder_id, shares) VALUES (?, ?, ?) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = shares + excluded.shares, updated_at = CURRENT_TIMESTAMP').bind(business.id, recipientId, shares),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, buyerAccount.account_id, ownerAccount.account_id, total, 'CREDIT', 'share_issuance', business.id, 'shares-v1', correlationId),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', business.id, business.owner_id, recipientId, shares, 'share_issuance', correlationId, day),
        env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, 'business.shares_issued', `Shares issued by ${business.id}`, JSON.stringify({ businessId: business.id, recipientId, shares, pricePerShare, total })),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), recipientId, 'ownership', 'Business shares received', `You acquired ${shares} shares in ${business.id}.`, business.id),
        ...existingHolders.map((holder) => env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), holder.holder_id, 'ownership', 'Business share issuance notice', `${shares} new shares were issued in ${business.id} at ${pricePerShare} Credits per share. Review your ownership percentage.`, business.id)),
      ]);
      return Response.json({ ok: true, businessId: business.id, recipientId, shares, pricePerShare, total, correlationId, holdings: (await env.DB.prepare('SELECT holder_id, shares FROM business_shares WHERE business_id = ? ORDER BY shares DESC').bind(business.id).all()).results, persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'GET') {
      const viewer = await currentHuman(request, env);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => getSuccessorPostgres(repository, viewer.id));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      return Response.json({ successor: await env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewer.id).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/life/status' && request.method === 'GET') {
      const viewer = await currentHuman(request, env, true);
      if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
      if (authorityMode(env) === 'postgres') {
        const result = await withRepository(env, (repository) => getLifeStatusPostgres(repository, viewer.id));
        if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const [human, succession, events] = await Promise.all([
        env.DB.prepare('SELECT id, display_name, age_years, life_status, death_game_day, standing, legacy FROM humans WHERE id = ?').bind(viewer.id).first(),
        env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewer.id).first(),
        env.DB.prepare('SELECT * FROM life_events WHERE human_id = ? ORDER BY game_day DESC LIMIT 20').bind(viewer.id).all(),
      ]);
      return Response.json({ ok: true, human, succession, events: events.results, persistence: 'cloudflare-d1' });
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
      if (authorityMode(env) === 'postgres') {
        try {
          if (viewer.life_status === 'estate') {
            if (!successorHumanId) return Response.json({ ok: false, error: 'An Estate Period requires an existing active Successor Human' }, { status: 400 });
            const world = await withRepository(env, (repository) => repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'"));
            const day = Number(world?.rows[0]?.game_day ?? 0);
            const result = await withRepository(env, (repository) => settleInheritancePostgres(repository, { predecessorId: viewer.id, successorId: successorHumanId, successorName, day }));
            if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
          }
          const result = await withRepository(env, (repository) => registerSuccessorPostgres(repository, { humanId: viewer.id, successorName, estatePeriodDays, successorHumanId, currentLifeStatus: viewer.life_status }));
          if (result) return Response.json({ ...result, persistence: 'planetscale-postgres' });
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Successor registration failed';
          return Response.json({ ok: false, error: message }, { status: message.includes('another active') ? 400 : 409 });
        }
      }
      if (successorHumanId && (successorHumanId === viewer.id || !(await env.DB.prepare("SELECT id FROM humans WHERE id = ? AND life_status = 'active'").bind(successorHumanId).first()))) return Response.json({ ok: false, error: 'Successor Human must be another active Human' }, { status: 400 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      if (viewer.life_status === 'estate') {
        if (!successorHumanId) return Response.json({ ok: false, error: 'An Estate Period requires an existing active Successor Human' }, { status: 400 });
        const [account, machines, businesses, shares, resources] = await Promise.all([
          env.DB.prepare("SELECT account_id, balance FROM account_balances WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id).first<{ account_id: string; balance: number }>(),
          env.DB.prepare('SELECT id FROM machines WHERE owner_id = ?').bind(viewer.id).all<{ id: string }>(),
          env.DB.prepare('SELECT id FROM businesses WHERE owner_id = ?').bind(viewer.id).all<{ id: string }>(),
          env.DB.prepare('SELECT business_id, shares FROM business_shares WHERE holder_id = ?').bind(viewer.id).all<{ business_id: string; shares: number }>(),
          env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind(viewer.id).all<{ resource: string; amount: number }>(),
        ]);
        const gross = Math.max(0, Number(account?.balance ?? 0));
        const tax = Math.round(gross * 0.2 * 100) / 100;
        const inherited = Math.max(0, gross - tax);
        const eventId = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare("UPDATE account_balances SET balance = 0 WHERE owner_id = ? AND currency = 'CREDIT'").bind(viewer.id),
          env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE owner_id = ? AND currency = 'CREDIT'").bind(inherited, successorHumanId),
          ...(tax > 0 ? [env.DB.prepare("UPDATE account_balances SET balance = balance + ? WHERE account_id = 'account-ouc-treasury'").bind(tax)] : []),
          env.DB.prepare('UPDATE humans SET standing = 0, legacy = legacy + 1 WHERE id = ?').bind(successorHumanId),
          env.DB.prepare('UPDATE machines SET owner_id = ? WHERE owner_id = ?').bind(successorHumanId, viewer.id),
          env.DB.prepare('UPDATE businesses SET owner_id = ? WHERE owner_id = ?').bind(successorHumanId, viewer.id),
          env.DB.prepare('UPDATE business_shares SET holder_id = ? WHERE holder_id = ?').bind(successorHumanId, viewer.id),
          ...resources.results.map((row) => env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(successorHumanId, row.resource, row.amount)),
          env.DB.prepare('DELETE FROM resource_balances WHERE owner_id = ?').bind(viewer.id),
          env.DB.prepare("UPDATE humans SET life_status = 'deceased' WHERE id = ?").bind(viewer.id),
          env.DB.prepare('INSERT OR REPLACE INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, death_game_day, standing, legacy, ? FROM humans WHERE id = ?').bind(successorName, viewer.id),
          env.DB.prepare('INSERT INTO life_events (id, human_id, event_type, game_day, successor_name, estate_credits) VALUES (?, ?, ?, ?, ?, ?)').bind(eventId, successorHumanId, 'inheritance', day, successorName, inherited),
          env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, viewer.id, successorHumanId, inherited, 'CREDIT', 'late_inheritance', eventId, 'life-v2', eventId),
          ...(tax > 0 ? [env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), day, viewer.id, 'account-ouc-treasury', tax, 'CREDIT', 'late_inheritance_tax', eventId, 'life-v2', eventId)] : []),
          ...machines.results.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', asset.id, viewer.id, successorHumanId, 1, 'late_inheritance', eventId, day)),
          ...businesses.results.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS', asset.id, viewer.id, successorHumanId, 1, 'late_inheritance', eventId, day)),
          ...shares.results.map((asset) => env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'BUSINESS_SHARES', asset.business_id, viewer.id, successorHumanId, asset.shares, 'late_inheritance', eventId, day)),
          env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), successorHumanId, 'life', 'Late inheritance received', `${inherited} Credits and your predecessor’s registered assets were transferred after the Estate Period.`, eventId),
          env.DB.prepare('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES (?, ?, ?, ?, ?)').bind(`LATE-INHERITANCE-${viewer.id}-${day}`, day, 'human.life_event', 'An Estate completed late succession', JSON.stringify({ predecessor: viewer.id, successor: successorHumanId, tax })),
          env.DB.prepare('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = ? AND revoked_at IS NULL').bind(viewer.id),
        ]);
        return Response.json({ ok: true, lateSuccession: true, successorHumanId, inherited, tax, eventId, persistence: 'cloudflare-d1' });
      }
      await env.DB.prepare('INSERT INTO succession_plans (human_id, successor_name, registered_game_day, estate_period_days, successor_human_id) VALUES (?, ?, ?, ?, ?) ON CONFLICT(human_id) DO UPDATE SET successor_name = excluded.successor_name, registered_game_day = excluded.registered_game_day, estate_period_days = excluded.estate_period_days, successor_human_id = excluded.successor_human_id').bind(viewer.id, successorName, day, estatePeriodDays, successorHumanId).run();
      return Response.json({ ok: true, successor: await env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind(viewer.id).first(), persistence: 'cloudflare-d1' });
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
      const machine = await env.DB.prepare('SELECT * FROM machines WHERE id = ? AND owner_id = ?').bind(decommissionMatch[1], viewer.id).first<Record<string, unknown>>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found for this Human' }, { status: 404 });
      const body = await request.json<{ otp?: string }>();
      if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) return Response.json({ ok: false, error: 'Authenticator code required for decommissioning an asset' }, { status: 401 });
      const embeddedMaterial: Record<string, number> = { extractor: 80, 'energy-array': 60, 'compute-node': 100, fabricator: 90, 'housing-fabricator': 110, 'research-cluster': 140, 'service-robot': 45 };
      const efficiency = Math.min(0.8, Math.max(0.2, 0.25 + Number(machine.condition ?? 0) / 200));
      const materialReturned = Math.round((embeddedMaterial[String(machine.machine_type)] ?? 60) * efficiency * 100) / 100;
      const componentsReturned = Math.round((Number(machine.productive_capacity ?? 1) * 25 * efficiency) * 100) / 100;
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const eventId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('DELETE FROM business_assets WHERE machine_id = ?').bind(machine.id),
        env.DB.prepare('DELETE FROM machines WHERE id = ? AND owner_id = ?').bind(machine.id, viewer.id),
        env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, \'material\', ?), (?, \'components\', ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(viewer.id, materialReturned, viewer.id, componentsReturned),
        env.DB.prepare('INSERT INTO recycling_events (id, machine_id, owner_id, material_returned, components_returned, efficiency, game_day) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(eventId, machine.id, viewer.id, materialReturned, componentsReturned, efficiency, day),
        env.DB.prepare('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), 'MACHINE', machine.id, viewer.id, null, 1, 'recycling', eventId, day),
        env.DB.prepare('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES (?, ?, ?, ?, ?, ?)').bind(crypto.randomUUID(), viewer.id, 'production', 'Machine recycled', `${materialReturned} Material and ${componentsReturned} Components returned at ${Math.round(efficiency * 100)}% efficiency.`, machine.id),
      ]);
      return Response.json({ ok: true, eventId, machineId: machine.id, materialReturned, componentsReturned, efficiency, persistence: 'cloudflare-d1' });
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
    // The handler still contains historical D1 compatibility branches. Keep
    // the provider boundary at the edge so no data request can reach one when
    // PostgreSQL is not explicitly configured as the authority.
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
