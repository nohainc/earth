import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8929;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie = '';
let contractId = '';

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) break; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const login = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: 'amara@earthuc.com', password: 'password123456' }) });
  assert.equal(login.status, 200);
  cookie = login.headers.get('set-cookie')?.split(';')[0] || '';
});
after(() => server?.kill());

async function request(path, options = {}) {
  const headers = { ...(options.body ? { 'content-type': 'application/json' } : {}), ...(options.headers || {}) };
  if (cookie) headers.cookie = cookie;
  const response = await fetch(`${base}${path}`, { ...options, headers, body: options.body && JSON.stringify(options.body) });
  return { response, body: await response.json() };
}

test('Tier 1 contracts API protects personal agreements and mutations', async () => {
  const list = await fetch(`${base}/api/contracts`);
  assert.equal(list.status, 401);
  const create = await fetch(`${base}/api/contracts`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ title: 'Unauthenticated offer' }) });
  assert.equal(create.status, 401);
});

test('Tier 2 contracts API returns scoped list, detail, and safe supply records', async () => {
  const list = await request('/api/contracts');
  const detail = await request('/api/contracts/CTR-001');
  const supply = await request('/api/contracts/supply');
  assert.equal(list.response.status, 200);
  assert.ok(list.body.contracts.some((contract) => contract.id === 'CTR-001'));
  assert.equal(detail.body.contract.id, 'CTR-001');
  assert.ok(Array.isArray(supply.body.supplyContracts));
  assert.doesNotMatch(JSON.stringify({ list, detail, supply }), /password|session_token|password_hash/i);
});

test('Tier 3 contracts API proposes, accepts, disputes, and resolves an agreement', async () => {
  const created = await request('/api/contracts', { method: 'POST', body: { kind: 'capacity', counterpartyId: 'H-0045', title: 'QA Capacity Agreement', amount: 250, durationDays: 10 } });
  assert.equal(created.response.status, 200);
  contractId = created.body.contract.id;
  const accepted = await request(`/api/contracts/${contractId}/accept`, { method: 'POST', body: {} });
  assert.equal(accepted.response.status, 200);
  assert.equal(accepted.body.contract.status, 'accepted');
  const disputed = await request(`/api/contracts/${contractId}/dispute`, { method: 'POST', body: { reason: 'Capacity was not delivered.' } });
  assert.equal(disputed.response.status, 200);
  const resolved = await request(`/api/contracts/${contractId}/resolve`, { method: 'POST', body: { outcome: 'refund', resolution: 'Refund approved by arbitration.' } });
  assert.equal(resolved.response.status, 200);
  assert.equal(resolved.body.contract.status, 'refunded');
});

test('Tier 4 contracts API rejects invalid terms, duplicate transitions, and unknown targets', async () => {
  const invalid = await request('/api/contracts', { method: 'POST', body: { title: 'x', amount: 0, durationDays: 0 } });
  assert.equal(invalid.response.status, 400);
  const duplicate = await request(`/api/contracts/${contractId}/dispute`, { method: 'POST', body: { reason: 'Duplicate dispute' } });
  assert.equal(duplicate.response.status, 409);
  const unknown = await request('/api/contracts/CON-UNKNOWN/accept', { method: 'POST', body: {} });
  assert.equal(unknown.response.status, 404);
});

test('Tier 5 supply contracts API supports proposal, scoped ticks, and idempotent cancellation', async () => {
  const proposed = await request('/api/contracts/supply/propose', { method: 'POST', body: { resourceType: 'energy', dailyQuantity: 5, unitPrice: 2, totalDays: 4, counterpartyId: 'H-0012' } });
  assert.equal(proposed.response.status, 200);
  const id = proposed.body.contractId;
  const ticks = await request(`/api/contracts/${id}/ticks`);
  assert.equal(ticks.response.status, 200);
  const cancelled = await request(`/api/contracts/${id}/cancel`, { method: 'POST', body: {} });
  assert.equal(cancelled.response.status, 200);
  const repeated = await request(`/api/contracts/${id}/cancel`, { method: 'POST', body: {} });
  assert.equal(repeated.response.status, 409);
});
