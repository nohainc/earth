import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const baseUrl = (process.env.EARTH_REMOTE_URL || 'https://earthuc.com').replace(/\/$/, '');
const schemaManifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));

async function get(path, options) {
  const response = await fetch(`${baseUrl}${path}`, options);
  const body = await response.json();
  return { response, body };
}

const appResponse = await fetch(`${baseUrl}/app`);
assert.equal(appResponse.status, 200);
const appHtml = await appResponse.text();
assert.match(appHtml, /flutter_bootstrap|main\.dart\.js/);

for (const landingPath of ['/', '/landing']) {
  const landingResponse = await fetch(`${baseUrl}${landingPath}`);
  assert.equal(landingResponse.status, 200);
  const landingHtml = await landingResponse.text();
  assert.match(landingHtml, /EARTH|United Corporations/);
  assert.match(landingHtml, /\/app/);
}

for (const readyPath of ['/ready', '/health', '/api/ready', '/api/health']) {
  const ready = await get(readyPath);
  assert.equal(ready.response.status, 200, `${readyPath} should return 200`);
  assert.equal(ready.response.headers.get('content-type')?.includes('application/json'), true, `${readyPath} must return JSON`);
  assert.equal(ready.body.ok, true, `${readyPath} must return ok: true`);
}

const live = await get('/api/live');
assert.equal(live.response.status, 200);
assert.deepEqual(live.body, { ok: true, status: 'live', correlationId: live.body.correlationId });

const health = await get(`/api/health?probe=${Date.now()}`);
assert.equal(health.response.status, 200);
assert.equal(typeof health.body.correlationId, 'string');
assert.equal(health.body.ok, true);
assert.equal(health.body.persistence, 'planetscale-postgres');
assert.equal(health.body.environment, 'production');
assert.equal(health.body.checks.database, true);
assert.equal(health.body.checks.coreSchema, true);
assert.equal(health.body.checks.featureSchema, true);
assert.equal(health.body.checks.marketCreditReservations, true);
assert.equal(health.body.checks.businessGovernanceSchema, true);
assert.equal(health.body.checks.balancesNonNegative, true);
assert.equal(health.body.checks.criticalInvariants, true);
assert.equal(health.body.checks.migrationManifest, true);
assert.equal(health.body.checks.schedulerFresh, true);
assert.equal(health.body.checks.outboxPressure, true);
assert.equal(health.body.checks.outboxRetryFailures, true);
assert.equal(typeof health.body.readiness.schedulerAgeSeconds, 'number');
assert.equal(typeof health.body.readiness.outboxPending, 'number');
assert.equal(typeof health.body.readiness.outboxRetryFailures, 'number');
assert.equal(health.body.schemaVersion, schemaManifest.migrationVersion);
assert.equal(health.body.expectedSchemaVersion, schemaManifest.migrationVersion);
assert.equal(health.body.readiness.migrationVersion, schemaManifest.migrationVersion);
assert.equal(health.body.readiness.invariantScan.ok, true);
assert.equal(health.body.readiness.invariantScan.balancesNonNegative, true);
assert.equal(health.body.checks.postgresConfigured, true);
assert.equal(health.body.checks.postgresReachable, true);
assert.equal(typeof health.body.checks.postgresSchemaReady, 'boolean');
assert.equal(typeof health.body.checks.postgresDataReady, 'boolean');
assert.equal(health.body.checks.postgresShadowParity, true);
assert.match(health.body.postgres.serverVersion, /^18\./);
assert.equal(health.body.migration.target, 'planetscale-postgres');
assert.equal(health.body.authority, 'postgres');

const liquidity = await get('/api/finance/liquidity');
assert.equal(liquidity.response.status, 401);
assert.equal(liquidity.body.ok, false);

const marketInstruments = await get('/api/market/instruments');
assert.equal(marketInstruments.response.status, 200);
assert.equal(marketInstruments.body.persistence, 'planetscale-postgres');
assert.equal(Array.isArray(marketInstruments.body.instruments), true);
for (const path of [
  '/api/institutions',
  '/api/rankings',
  '/api/history',
]) {
  const read = await get(path);
  assert.equal(read.response.status, 200, `${path} should be public`);
  assert.equal(read.body.persistence, 'planetscale-postgres', `${path} must use PostgreSQL`);
}

const governanceRoles = await get('/api/governance/roles');
assert.equal(governanceRoles.response.status, 401);
const governanceRules = await get('/api/governance/rules');
assert.equal(governanceRules.response.status, 401);
const technology = await get('/api/technology');
assert.equal(technology.response.status, 401);

const session = await get('/api/auth/me');
assert.equal(session.response.status, 200);
assert.equal(session.body.authenticated, false);

const resendVerification = await get('/api/auth/verify-email/resend', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email: `smoke-${Date.now()}@example.invalid` }),
});
assert.equal(resendVerification.response.status, 200);
assert.equal(resendVerification.body.ok, true);
assert.match(resendVerification.body.message, /If that identity exists and needs verification/);

const malformedPublicBody = await get('/api/auth/verify-email/resend', {
  method: 'POST',
  headers: { 'content-type': 'application/json', 'X-Request-ID': 'smoke-malformed-json' },
  body: '{',
});
assert.equal(malformedPublicBody.response.status, 400);
assert.equal(malformedPublicBody.body.code, 'VALIDATION_ERROR');
assert.equal(malformedPublicBody.body.correlationId, 'smoke-malformed-json');

const world = await get('/api/world', { headers: { 'X-Request-ID': 'smoke-error-contract' } });
assert.equal(world.response.status, 401);
assert.equal(world.body.error, 'Authentication required');
assert.equal(world.body.code, 'AUTHENTICATION_REQUIRED');
assert.equal(world.body.correlationId, 'smoke-error-contract');

const opportunities = await get('/api/world');
assert.equal(opportunities.response.status, 401);
assert.equal(opportunities.body.code, 'AUTHENTICATION_REQUIRED');

const marketOrder = await get('/api/market/orders', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ product: 'energy', side: 'buy', quantity: 1, limitPrice: 1, correlationId: 'smoke-market-order' }) });
assert.equal(marketOrder.response.status, 401);
assert.equal(marketOrder.body.error, 'Authentication required');

const publicSpending = await get('/api/finance/public-spending', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ cityId: 'CITY-0084', category: 'public-services', amount: 100, correlationId: 'smoke-public-spending' }),
});
assert.equal(publicSpending.response.status, 401);
assert.equal(publicSpending.body.error, 'Authentication required');

const corporationSpending = await get('/api/corporations/CORP-001/treasury/spend', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ amount: 100, correlationId: 'smoke-corporation-spending' }),
});
assert.equal(corporationSpending.response.status, 401);
assert.equal(corporationSpending.body.error, 'Authentication required');
const corporationContribution = await get('/api/corporations/CORP-001/contributions', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ amount: 100, correlationId: 'smoke-corporation-contribution' }),
});
assert.equal(corporationContribution.response.status, 401);
assert.equal(corporationContribution.body.error, 'Authentication required');

const proposals = await get('/api/governance/proposals');
assert.equal(proposals.response.status, 401);

const realtime = await get('/api/realtime');
assert.equal(realtime.response.status, 401);
assert.equal(realtime.body.error, 'Authentication required');

const services = await get('/api/services/status');
assert.equal(services.response.status, 401);
assert.equal(services.body.error, 'Authentication required');

const personalFinance = await get('/api/finance/personal');
assert.equal(personalFinance.response.status, 401);
assert.equal(personalFinance.body.error, 'Authentication required');
const personalBankruptcy = await get('/api/finance/personal/declare', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({}) });
assert.equal(personalBankruptcy.response.status, 401);
assert.equal(personalBankruptcy.body.error, 'Authentication required');


const residency = await get('/api/cities/CITY-0084/residency', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ correlationId: 'smoke-residency' }) });
assert.equal(residency.response.status, 401);
assert.equal(residency.body.error, 'Authentication required');


const communityCreate = await get('/api/communities', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Smoke Community', correlationId: 'smoke-community-formation' }) });
assert.equal(communityCreate.response.status, 401);
assert.equal(communityCreate.body.error, 'Authentication required');
const communityContribution = await get('/api/communities/COMM-SMOKE/contributions', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ amount: 50, correlationId: 'smoke-community-contribution' }) });
assert.equal(communityContribution.response.status, 401);
assert.equal(communityContribution.body.error, 'Authentication required');

const researchFunding = await get('/api/technology/me/fund', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ amount: 240, correlationId: 'smoke-research-funding' }) });
assert.equal(researchFunding.response.status, 401);
assert.equal(researchFunding.body.error, 'Authentication required');

const researchProject = await get('/api/technology/projects', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Smoke Research', budget: 240, focus: 'efficiency', correlationId: 'smoke-research-project' }) });
assert.equal(researchProject.response.status, 401);
assert.equal(researchProject.body.error, 'Authentication required');

const proposalCreate = await get('/api/governance/proposals', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ institutionId: 'OUC-001', title: 'Smoke Proposal', body: 'Smoke proposal body for authentication testing', correlationId: 'smoke-governance-proposal' }) });
assert.equal(proposalCreate.response.status, 401);
assert.equal(proposalCreate.body.error, 'Authentication required');

const membershipEvents = await get('/api/membership/events');
assert.equal(membershipEvents.response.status, 404);
assert.equal(membershipEvents.body.error, 'API route not found');


console.log(`EARTH remote smoke passed: ${baseUrl}`);
