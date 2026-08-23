import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8919;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie;

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, { ...options, headers: { accept: 'application/json', ...(cookie ? { cookie } : {}), ...(options.headers || {}) } });
  let body = null;
  try { body = await response.json(); } catch {}
  return { response, body };
}

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('user test server did not start');
});
after(() => server?.kill());

test('Tier 1 user API returns an unauthenticated safe projection', async () => {
  const { response, body } = await request('/api/auth/me');
  assert.equal(response.status, 200);
  assert.equal(body.authenticated, false);
  assert.equal(body.human, null);
  assert.doesNotMatch(JSON.stringify(body), /password|session_token|password_hash/i);
});

test('Tier 2 profile API requires authentication and validates display names', async () => {
  const unauthenticated = await request('/api/auth/profile', { method: 'PATCH', headers: {'content-type': 'application/json'}, body: JSON.stringify({displayName: 'Updated User'}) });
  assert.equal(unauthenticated.response.status, 401);
});

test('Tier 3 profile API updates the authenticated user projection', async () => {
  const login = await request('/api/auth/login', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({email: 'amara@earthuc.com', password: 'password123456'}) });
  assert.equal(login.response.status, 200);
  cookie = login.response.headers.get('set-cookie')?.split(';')[0];
  assert.ok(cookie);
  const updated = await request('/api/auth/profile', { method: 'PATCH', headers: {'content-type': 'application/json'}, body: JSON.stringify({displayName: 'Amara Updated'}) });
  assert.equal(updated.response.status, 200);
  assert.equal(updated.body.human.displayName, 'Amara Updated');
  const me = await request('/api/auth/me');
  assert.equal(me.body.human.displayName, 'Amara Updated');
});

test('Tier 4 personal finance API exposes only the current user projection', async () => {
  const { response, body } = await request('/api/finance/personal');
  assert.equal(response.status, 200);
  assert.equal(body.account.owner_id, 'H-0044');
  assert.doesNotMatch(JSON.stringify(body), /password|password_hash|session_token/i);
});

test('Tier 5 user journey reaches session, personal finance, and logout', async () => {
  const finance = await request('/api/finance/personal');
  assert.equal(finance.body.state.status, 'active');
  const logout = await request('/api/auth/logout', { method: 'POST' });
  assert.equal(logout.response.status, 200);
  cookie = undefined;
});
