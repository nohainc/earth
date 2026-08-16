import { readFile } from 'node:fs/promises';

const wrangler = await readFile(new URL('../wrangler.api.jsonc', import.meta.url), 'utf8');
const workerTypes = await readFile(new URL('../worker-configuration.d.ts', import.meta.url), 'utf8');
const repository = await readFile(new URL('../cloudflare/src/repository.ts', import.meta.url), 'utf8');
const worker = await readFile(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');
const authSession = await readFile(new URL('../cloudflare/src/auth-session.ts', import.meta.url), 'utf8');
const scheduler = await readFile(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');

if (/d1_databases|"DB"\s*:/.test(wrangler)) throw new Error('D1 bindings must not be configured for EARTH');
if (!wrangler.includes('"PERSISTENCE_AUTHORITY": "postgres"')) throw new Error('PostgreSQL authority must be configured');
if (!wrangler.includes('"binding": "HYPERDRIVE"')) throw new Error('Hyperdrive binding is required');
if (/\bDB\s*:\s*D1Database/.test(workerTypes)) throw new Error('Generated Worker types must not expose a DB binding');
if (!repository.includes('PostgreSQL persistence authority is required')) throw new Error('Repository must fail closed on non-PostgreSQL authority');
if (!worker.includes('if (isDataRequest) authorityMode(env);')) throw new Error('Worker data boundary must fail closed before routing requests');
if (!worker.includes('String(_event.scheduledTime)')) throw new Error('Scheduled world ticks must carry an idempotency key');
if (!scheduler.includes('SCHEDULED-TICK-')) throw new Error('Scheduled world ticks must persist an atomic replay marker');
if (!worker.includes('async function advanceWorldFromPostgres')) throw new Error('World-clock command must have a PostgreSQL-only handler');
if (!worker.includes("if (url.pathname === '/api/day/advance' && request.method === 'POST') return advanceWorldFromPostgres(request, env);")) throw new Error('World-clock command must bypass legacy provider branches');
if (!worker.includes('async function productionEventsFromPostgres')) throw new Error('Production history must have a PostgreSQL-only handler');
if (!worker.includes("if (url.pathname === '/api/production/events' && request.method === 'GET') return productionEventsFromPostgres(request, env);")) throw new Error('Production history must bypass legacy provider branches');
if (!worker.includes('async function servicesStatusFromPostgres')) throw new Error('Service status must have a PostgreSQL-only handler');
if (!worker.includes("if (url.pathname === '/api/services/status' && request.method === 'GET') return servicesStatusFromPostgres(request, env);")) throw new Error('Service status must bypass legacy provider branches');
for (const [handler, route] of [
  ['worldActivityFromPostgres', "if (url.pathname === '/api/world/activity' && request.method === 'GET') return worldActivityFromPostgres(request, env);"],
  ['eventsFromPostgres', "if (url.pathname === '/api/events' && request.method === 'GET') return eventsFromPostgres(request, env);"],
  ['notificationsFromPostgres', "if (url.pathname === '/api/notifications' && request.method === 'GET') return notificationsFromPostgres(request, env);"],
  ['auditFromPostgres', "if (url.pathname === '/api/audit' && request.method === 'GET') return auditFromPostgres(request, env);"],
]) {
  if (!worker.includes(`async function ${handler}`)) throw new Error(`${handler} is required for PostgreSQL authority`);
  if (!worker.includes(route)) throw new Error(`${handler} must bypass legacy provider branches`);
}
for (const [handler, route] of [
  ['institutionsFromPostgres', "if (url.pathname === '/api/institutions' && request.method === 'GET') return institutionsFromPostgres(request, env);"],
  ['rankingsFromPostgres', "if (url.pathname === '/api/rankings' && request.method === 'GET') return rankingsFromPostgres(request, env);"],
  ['historyFromPostgres', "if (url.pathname === '/api/history' && request.method === 'GET') return historyFromPostgres(request, env);"],
  ['ownershipHistoryFromPostgres', "if (url.pathname === '/api/ownership/events' && request.method === 'GET') return ownershipHistoryFromPostgres(request, env);"],
  ['membershipHistoryFromPostgres', "if (url.pathname === '/api/membership/events' && request.method === 'GET') return membershipHistoryFromPostgres(request, env);"],
  ['authorityHistoryFromPostgres', "if (url.pathname === '/api/governance/authority/events' && request.method === 'GET') return authorityHistoryFromPostgres(request, env);"],
]) {
  if (!worker.includes(`async function ${handler}`)) throw new Error(`${handler} is required for PostgreSQL authority`);
  if (!worker.includes(route)) throw new Error(`${handler} must bypass legacy provider branches`);
}
if (!wrangler.includes('"EMAIL_FROM": "earth@auth.earthuc.com"')) throw new Error('EARTH transactional sender must use the authenticated Cloudflare sending domain');
if (!wrangler.includes('"EMAIL_REPLY_TO": "earth@nohainc.com"')) throw new Error('EARTH transactional reply-to must remain earth@nohainc.com');
if (!authSession.includes('from: { email: env.EMAIL_FROM')) throw new Error('EARTH transactional sender must be configuration-driven');
console.log(JSON.stringify({ ok: true, authority: 'postgres', d1Binding: false, hyperdrive: true }));
