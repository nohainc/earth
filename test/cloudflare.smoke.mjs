import assert from 'node:assert/strict';

const baseUrl = (process.env.EARTH_REMOTE_URL || 'https://earthuc.com').replace(/\/$/, '');

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

const health = await get(`/api/health?probe=${Date.now()}`);
assert.equal(health.response.status, 200);
assert.equal(health.body.ok, true);
assert.equal(health.body.persistence, 'planetscale-postgres');
assert.equal(health.body.environment, 'production');
assert.equal(health.body.checks.database, true);
assert.equal(health.body.checks.coreSchema, true);
assert.equal(health.body.checks.featureSchema, true);
assert.equal(health.body.checks.maintenanceIdempotency, true);
assert.equal(health.body.checks.marketCreditReservations, true);
assert.equal(health.body.checks.businessGovernanceSchema, true);
assert.equal(health.body.checks.balancesNonNegative, true);
assert.equal(health.body.checks.machineConditionsBounded, true);
assert.equal(health.body.checks.postgresConfigured, true);
assert.equal(health.body.checks.postgresReachable, true);
assert.equal(typeof health.body.checks.postgresSchemaReady, 'boolean');
assert.equal(typeof health.body.checks.postgresDataReady, 'boolean');
assert.equal(health.body.checks.postgresShadowParity, true);
assert.match(health.body.postgres.serverVersion, /^18\./);
assert.equal(health.body.migration.target, 'planetscale-postgres');
assert.equal(health.body.authority, 'postgres');

const liquidity = await get('/api/finance/liquidity');
assert.equal(liquidity.response.status, 200);
assert.equal(liquidity.body.persistence, 'planetscale-postgres');
assert.equal(typeof liquidity.body.activeHumans, 'number');
assert.equal(typeof liquidity.body.moneySupply, 'number');
assert.equal(typeof liquidity.body.target, 'number');
assert.ok(['below-corridor', 'inside-corridor', 'above-corridor'].includes(liquidity.body.status));

const marketBook = await get('/api/market/book');
assert.equal(marketBook.response.status, 200);
assert.equal(typeof marketBook.body.feeRate, 'number');
for (const path of [
  '/api/institutions',
  '/api/governance/roles',
  '/api/governance/rules',
  '/api/rankings',
  '/api/history',
  '/api/cities',
  '/api/corporations',
  '/api/technology',
]) {
  const read = await get(path);
  assert.equal(read.response.status, 200, `${path} should be public`);
  assert.equal(read.body.persistence, 'planetscale-postgres', `${path} must use PostgreSQL`);
}

const catalog = await get('/api/production/catalog');
assert.equal(catalog.response.status, 200);
assert.equal(catalog.body.persistence, 'planetscale-postgres');
assert.ok(Array.isArray(catalog.body.sectors));
for (const sector of catalog.body.sectors) {
  assert.ok(Array.isArray(sector.machineTypes));
  if (sector.acquisition) {
    assert.equal(typeof sector.acquisition.credit, 'number');
    assert.equal(typeof sector.acquisition.material, 'number');
  }
}

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

const world = await get('/api/world', { headers: { 'X-Request-ID': 'smoke-error-contract' } });
assert.equal(world.response.status, 401);
assert.equal(world.body.error, 'Authentication required');
assert.equal(world.body.code, 'AUTHENTICATION_REQUIRED');
assert.equal(world.body.correlationId, 'smoke-error-contract');

const marketCommand = await get('/edge/market', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(marketCommand.response.status, 401);
assert.equal(marketCommand.body.error, 'Authentication required');
assert.equal(marketCommand.body.code, 'AUTHENTICATION_REQUIRED');
assert.equal(typeof marketCommand.body.correlationId, 'string');
const marketOrder = await get('/api/market/orders', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ product: 'energy', side: 'buy', quantity: 1, limitPrice: 1, correlationId: 'smoke-market-order' }) });
assert.equal(marketOrder.response.status, 401);
assert.equal(marketOrder.body.error, 'Authentication required');
const marketSnapshot = await get('/edge/market');
assert.equal(marketSnapshot.response.status, 401);
assert.equal(marketSnapshot.body.error, 'Authentication required');

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
assert.equal(proposals.response.status, 200);
assert.ok(Array.isArray(proposals.body.proposals));
assert.equal(proposals.body.persistence, 'planetscale-postgres');

const ownership = await get('/api/ownership/events');
assert.equal(ownership.response.status, 401);
assert.equal(ownership.body.error, 'Authentication required');

const liveEvents = await get('/edge/events');
assert.equal(liveEvents.response.status, 401);
assert.equal(liveEvents.body.error, 'Authentication required');

const productionEvents = await get('/api/production/events');
assert.equal(productionEvents.response.status, 401);
assert.equal(productionEvents.body.error, 'Authentication required');

const services = await get('/api/services/status');
assert.equal(services.response.status, 401);
assert.equal(services.body.error, 'Authentication required');

const personalFinance = await get('/api/finance/personal');
assert.equal(personalFinance.response.status, 401);
assert.equal(personalFinance.body.error, 'Authentication required');
const personalBankruptcy = await get('/api/finance/personal/declare', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({}) });
assert.equal(personalBankruptcy.response.status, 401);
assert.equal(personalBankruptcy.body.error, 'Authentication required');

const roleDelegation = await get('/api/governance/roles/ROLE-OUC-DELEGATE/delegate', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ delegateHumanId: 'H-SMOKE' }) });
assert.equal(roleDelegation.response.status, 401);
assert.equal(roleDelegation.body.error, 'Authentication required');
const roleRecall = await get('/api/governance/roles/ROLE-OUC-DELEGATE/recall', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(roleRecall.response.status, 401);
assert.equal(roleRecall.body.error, 'Authentication required');

const contracts = await get('/api/contracts');
assert.equal(contracts.response.status, 401);
assert.equal(contracts.body.error, 'Authentication required');
const contractCreate = await get('/api/contracts', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ kind: 'capacity', counterpartyId: 'H-SMOKE', title: 'Smoke capacity agreement', amount: 10, durationDays: 30 }) });
assert.equal(contractCreate.response.status, 401);
assert.equal(contractCreate.body.error, 'Authentication required');

const residency = await get('/api/cities/CITY-0084/residency', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ correlationId: 'smoke-residency' }) });
assert.equal(residency.response.status, 401);
assert.equal(residency.body.error, 'Authentication required');

const contractDispute = await get('/api/contracts/CON-SMOKE/dispute', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ reason: 'Smoke arbitration reason' }) });
assert.equal(contractDispute.response.status, 401);
assert.equal(contractDispute.body.error, 'Authentication required');
const contractResolve = await get('/api/contracts/CON-SMOKE/resolve', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ outcome: 'uphold', resolution: 'Smoke resolution record' }) });
assert.equal(contractResolve.response.status, 401);
assert.equal(contractResolve.body.error, 'Authentication required');

const decommission = await get('/api/machines/unknown/decommission', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(decommission.response.status, 401);
assert.equal(decommission.body.error, 'Authentication required');

const maintenance = await get('/api/machines/unknown/maintenance', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ amount: 10, correlationId: 'smoke-maintenance' }) });
assert.equal(maintenance.response.status, 401);
assert.equal(maintenance.body.error, 'Authentication required');

const ai = await get('/api/ai');
assert.equal(ai.response.status, 401);
assert.equal(ai.body.error, 'Authentication required');

const aiPolicy = await get('/api/ai/policy', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(aiPolicy.response.status, 401);
assert.equal(aiPolicy.body.error, 'Authentication required');

const aiUpgrade = await get('/api/ai/upgrade', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(aiUpgrade.response.status, 401);
assert.equal(aiUpgrade.body.error, 'Authentication required');

const machineUpgrade = await get('/api/machines/unknown/upgrade', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(machineUpgrade.response.status, 401);
assert.equal(machineUpgrade.body.error, 'Authentication required');

const machineSale = await get('/api/machines/unknown/sell', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
assert.equal(machineSale.response.status, 401);
assert.equal(machineSale.body.error, 'Authentication required');

const machineAcquire = await get('/api/machines/acquire', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ machineType: 'extractor', correlationId: 'smoke-machine-acquisition' }) });
assert.equal(machineAcquire.response.status, 401);
assert.equal(machineAcquire.body.error, 'Authentication required');

const businessCreate = await get('/api/businesses', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Smoke Business', sector: 'energy', correlationId: 'smoke-business-registration' }) });
assert.equal(businessCreate.response.status, 401);
assert.equal(businessCreate.body.error, 'Authentication required');
const businessConstitution = await get('/api/businesses/B-SMOKE/constitution');
assert.equal(businessConstitution.response.status, 401);
assert.equal(businessConstitution.body.error, 'Authentication required');
const businessConstitutionUpdate = await get('/api/businesses/B-SMOKE/constitution', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ shareholderVoteThreshold: 0.5, boardApprovalThreshold: 0.5, dilutionNoticeDays: 3 }) });
assert.equal(businessConstitutionUpdate.response.status, 401);
assert.equal(businessConstitutionUpdate.body.error, 'Authentication required');
const businessManager = await get('/api/businesses/B-SMOKE/manager', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ managerId: 'H-SMOKE' }) });
assert.equal(businessManager.response.status, 401);
assert.equal(businessManager.body.error, 'Authentication required');
const businessOwnership = await get('/api/businesses/B-SMOKE/ownership');
assert.equal(businessOwnership.response.status, 401);
assert.equal(businessOwnership.body.error, 'Authentication required');

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
assert.equal(membershipEvents.response.status, 401);
assert.equal(membershipEvents.body.error, 'Authentication required');

const authorityEvents = await get('/api/governance/authority/events');
assert.equal(authorityEvents.response.status, 401);
assert.equal(authorityEvents.body.error, 'Authentication required');

console.log(`EARTH remote smoke passed: ${baseUrl}`);
