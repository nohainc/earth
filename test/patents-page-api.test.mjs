import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8933;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie = '';

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

async function request(path, options = {}, authenticated = true) {
  const headers = { ...(options.body ? { 'content-type': 'application/json' } : {}), ...(options.headers || {}) };
  if (authenticated) headers.cookie = cookie;
  const response = await fetch(`${base}${path}`, { ...options, headers, ...(options.body ? { body: JSON.stringify(options.body) } : {}) });
  return { response, body: await response.json() };
}

test('Tier 1 Patents API protects the portfolio and commercial mutations', async () => {
  for (const [path, method] of [['/api/technology', 'GET'], ['/api/technology/me/patent', 'POST'], ['/api/technology/me/license', 'POST']]) {
    const result = await request(path, { method, ...(method === 'POST' ? { body: {} } : {}) }, false);
    assert.equal(result.response.status, 401, path);
  }
});

test('Tier 2 Patents API returns safe patent and license records', async () => {
  const result = await request('/api/technology');
  assert.equal(result.response.status, 200);
  assert.ok(result.body.patents.every((patent) => patent.id && patent.status));
  assert.ok(result.body.licenses.every((license) => license.patent_id && license.licensee_id));
  assert.doesNotMatch(JSON.stringify(result.body), /password|session_token|password_hash/i);
});

test('Tier 3 Patents API grants a completed research patent and links a license', async () => {
  for (let i = 0; i < 7; i += 1) {
    const funding = await request('/api/technology/me/fund', { method: 'POST', body: { amount: 1 } });
    assert.equal(funding.response.status, 200);
  }
  const patent = await request('/api/technology/me/patent', { method: 'POST', body: {} });
  assert.equal(patent.response.status, 200);
  assert.equal(patent.body.patent.id, 'PAT-TECH-001');
  const license = await request('/api/technology/me/license', { method: 'POST', body: { licenseeId: 'H-0099', licenseFee: 50 } });
  assert.equal(license.response.status, 200);
  assert.equal(license.body.license.patent_id, patent.body.patent.id);
});

test('Tier 4 Patents API rejects invalid license terms and unknown routes', async () => {
  for (const body of [{ royaltyRate: -0.01 }, { royaltyRate: 1.01 }, { royaltyRate: 'NaN' }, { licenseFee: -1 }, { licenseFee: 'Infinity' }]) {
    const result = await request('/api/technology/me/license', { method: 'POST', body });
    assert.equal(result.response.status, 400);
  }
  const unknown = await request('/api/technology/UNKNOWN/patent', { method: 'POST', body: {} });
  assert.equal(unknown.response.status, 404);
});

test('Tier 5 Patents API preserves idempotent patent and license state', async () => {
  const repeatedPatent = await request('/api/technology/me/patent', { method: 'POST', body: {} });
  assert.equal(repeatedPatent.response.status, 200);
  assert.equal(repeatedPatent.body.state.technology.activePatents, 1);
  const first = await request('/api/technology/me/license', { method: 'POST', body: { licenseeId: 'H-0099', licenseFee: 75 } });
  const repeated = await request('/api/technology/me/license', { method: 'POST', body: { licenseeId: 'H-0099', licenseFee: 75 } });
  assert.equal(first.response.status, 200);
  assert.equal(repeated.response.status, 200);
  assert.equal(repeated.body.state.technology.activeLicenses, 2);
  assert.equal(repeated.body.license.id, first.body.license.id);
});
