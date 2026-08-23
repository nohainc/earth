import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8927;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie = '';
let acquiredId = '';

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

test('Tier 1 assets API protects personal machine inventory and mutations', async () => {
  const inventory = await fetch(`${base}/api/machines`);
  assert.equal(inventory.status, 401);
  const acquire = await fetch(`${base}/api/machines/acquire`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ machineType: 'fabrication-rig' }) });
  assert.equal(acquire.status, 401);
});

test('Tier 2 assets API returns owned machines with stable safe fields', async () => {
  const { response, body } = await request('/api/machines');
  assert.equal(response.status, 200);
  assert.ok(body.machines.length >= 1);
  assert.ok(body.machines.every((machine) => machine.owner_id === 'H-0044'));
  assert.doesNotMatch(JSON.stringify(body), /password|session_token|password_hash/i);
});

test('Tier 3 assets API acquires and manages a machine through its lifecycle', async () => {
  const acquired = await request('/api/machines/acquire', { method: 'POST', body: { machineType: 'fabrication-rig' } });
  assert.equal(acquired.response.status, 200);
  acquiredId = acquired.body.machine.id;
  const maintained = await request(`/api/machines/${acquiredId}/maintenance`, { method: 'POST', body: { amount: 5 } });
  assert.equal(maintained.response.status, 200);
  const utilization = await request(`/api/machines/${acquiredId}/utilization`, { method: 'POST', body: { utilization: 80 } });
  assert.equal(utilization.body.machine.utilization, 80);
  const workplace = await request(`/api/machines/${acquiredId}/workplace`, { method: 'POST', body: { businessId: 'B-1048' } });
  assert.equal(workplace.response.status, 200);
  assert.equal(workplace.body.machine.business_id, 'B-1048');
  const upgraded = await request(`/api/machines/${acquiredId}/upgrade`, { method: 'POST', body: {} });
  assert.equal(upgraded.response.status, 200);
  assert.equal(upgraded.body.machine.productive_capacity, 1.2);
});

test('Tier 4 assets API rejects invalid ranges and unknown workplace targets', async () => {
  const invalidUtilization = await request(`/api/machines/${acquiredId}/utilization`, { method: 'POST', body: { utilization: 101 } });
  assert.equal(invalidUtilization.response.status, 400);
  const invalidWorkplace = await request(`/api/machines/${acquiredId}/workplace`, { method: 'POST', body: { businessId: 'B-UNKNOWN' } });
  assert.equal(invalidWorkplace.response.status, 404);
  const invalidSale = await request(`/api/machines/${acquiredId}/sell`, { method: 'POST', body: { buyerId: 'H-0045', price: 0 } });
  assert.equal(invalidSale.response.status, 400);
});

test('Tier 5 assets API decommissions exactly once and preserves an audit-safe state', async () => {
  const recycled = await request(`/api/machines/${acquiredId}/decommission`, { method: 'POST', body: {} });
  assert.equal(recycled.response.status, 200);
  assert.equal(recycled.body.machine.status, 'recycled');
  const repeated = await request(`/api/machines/${acquiredId}/decommission`, { method: 'POST', body: {} });
  assert.equal(repeated.response.status, 409);
  const inventory = await request('/api/machines');
  assert.equal(inventory.body.machines.find((machine) => machine.id === acquiredId).status, 'recycled');
});
