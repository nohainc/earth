import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8932;
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
  if (authenticated && cookie) headers.cookie = cookie;
  const response = await fetch(`${base}${path}`, { ...options, headers, body: options.body && JSON.stringify(options.body) });
  return { response, body: await response.json() };
}

test('Tier 1 Research API protects personalized reads and mutations', async () => {
  for (const [path, method, body] of [
    ['/api/technology', 'GET'],
    ['/api/technology/projects', 'POST', { name: 'Unauthorized Project', budget: 240 }],
    ['/api/technology/me/fund', 'POST', { amount: 240 }],
    ['/api/technology/me/patent', 'POST', {}],
    ['/api/technology/me/license', 'POST', {}],
  ]) {
    const result = await request(path, { method, body }, false);
    assert.equal(result.response.status, 401, path);
  }
});

test('Tier 2 Research API returns a stable safe projection', async () => {
  const result = await request('/api/technology');
  assert.equal(result.response.status, 200);
  assert.ok(Array.isArray(result.body.projects));
  assert.ok(Array.isArray(result.body.patents));
  assert.ok(Array.isArray(result.body.licenses));
  assert.doesNotMatch(JSON.stringify(result.body), /password|session_token|password_hash/i);
});

test('Tier 3 Research API creates and funds a project', async () => {
  const project = await request('/api/technology/projects', { method: 'POST', body: { name: 'Resilient Systems', budget: 240, focus: 'durability' } });
  assert.equal(project.response.status, 200);
  assert.equal(project.body.project.name, 'Resilient Systems');
  assert.equal(project.body.project.progress, 0);
  const funded = await request('/api/technology/me/fund', { method: 'POST', body: { amount: 240 } });
  assert.equal(funded.response.status, 200);
  assert.equal(funded.body.research.progress, 4);
  assert.equal(funded.body.research.name, 'Resilient Systems');
});

test('Tier 4 Research API rejects invalid numeric and license inputs', async () => {
  for (const body of [{ name: 'Bad Budget', budget: 'NaN' }, { name: 'Bad Budget', budget: -1 }, { name: 'x', budget: 240 }]) {
    const result = await request('/api/technology/projects', { method: 'POST', body });
    assert.equal(result.response.status, 400);
  }
  for (const body of [{ amount: 'Infinity' }, { amount: -10 }, { amount: 'not-a-number' }]) {
    const result = await request('/api/technology/me/fund', { method: 'POST', body });
    assert.equal(result.response.status, 400);
  }
  for (const body of [{ royaltyRate: 1.1 }, { royaltyRate: -0.1 }, { licenseFee: -1 }, { licenseFee: 'Infinity' }]) {
    const result = await request('/api/technology/me/license', { method: 'POST', body });
    assert.equal(result.response.status, 400);
  }
});

test('Tier 5 Research API completes patent and idempotent licensing journey', async () => {
  const first = await request('/api/technology/me/patent', { method: 'POST', body: {} });
  assert.equal(first.response.status, 409);
  for (let i = 0; i < 24; i += 1) await request('/api/technology/me/fund', { method: 'POST', body: { amount: 1 } });
  const patent = await request('/api/technology/me/patent', { method: 'POST', body: {} });
  assert.equal(patent.response.status, 200);
  assert.equal(patent.body.patent.status, 'active');
  const license = await request('/api/technology/me/license', { method: 'POST', body: { licenseeId: 'H-0045', licenseFee: 100 } });
  assert.equal(license.response.status, 200);
  const repeated = await request('/api/technology/me/license', { method: 'POST', body: { licenseeId: 'H-0045', licenseFee: 100 } });
  assert.equal(repeated.response.status, 200);
  assert.equal(repeated.body.state.technology.activeLicenses, 2);
  assert.equal(repeated.body.license.patent_id, patent.body.patent.id);
});
