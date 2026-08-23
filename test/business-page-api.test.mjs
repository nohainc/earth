import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8926;
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

async function request(path, options = {}) {
  const headers = { ...(options.body ? { 'content-type': 'application/json' } : {}), ...(options.headers || {}) };
  if (cookie) headers.cookie = cookie;
  const response = await fetch(`${base}${path}`, { ...options, headers, body: options.body && JSON.stringify(options.body) });
  return { response, body: await response.json() };
}

test('Tier 1 business API protects personalized business data', async () => {
  for (const path of ['/api/businesses/B-1048', '/api/businesses/B-1048/financials', '/api/businesses/B-1048/ownership']) {
    const response = await fetch(`${base}${path}`);
    assert.equal(response.status, 401, path);
  }
});

test('Tier 2 business API exposes profile, financials, and ownership read models', async () => {
  const profile = await request('/api/businesses/B-1048');
  const financials = await request('/api/businesses/B-1048/financials');
  const ownership = await request('/api/businesses/B-1048/ownership');
  assert.equal(profile.body.business.id, 'B-1048');
  assert.equal(financials.body.business.profit, 420);
  assert.equal(ownership.body.totalIssuedShares, 1000);
  assert.equal(ownership.body.holders.reduce((sum, holder) => sum + holder.shares, 0), 1000);
  assert.doesNotMatch(JSON.stringify({ profile, financials, ownership }), /password|session_token|password_hash/i);
});

test('Tier 3 business API changes policy and distributes a dividend', async () => {
  const policy = await request('/api/businesses/B-1048/policy', { method: 'POST', body: { policy: 'margin' } });
  assert.equal(policy.response.status, 200);
  assert.equal(policy.body.policy, 'margin');
  const dividend = await request('/api/businesses/B-1048/dividends', { method: 'POST', body: { amount: 200 } });
  assert.equal(dividend.response.status, 200);
  assert.equal(dividend.body.amount, 200);
  assert.equal(dividend.body.state.business.policy, 'margin');
});

test('Tier 4 business API rejects invalid business targets and values', async () => {
  const unknown = await request('/api/businesses/B-UNKNOWN/financials');
  assert.equal(unknown.response.status, 404);
  const invalid = await request('/api/businesses/B-1048/dividends', { method: 'POST', body: { amount: 0 } });
  assert.equal(invalid.response.status, 400);
  const forbidden = await fetch(`${base}/api/businesses/B-1048/dividends`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ amount: 10 }) });
  assert.equal(forbidden.status, 401);
});

test('Tier 5 business API completes a guarded liquidation journey', async () => {
  const liquidated = await request('/api/businesses/B-1048/liquidate', { method: 'POST', body: {} });
  assert.equal(liquidated.response.status, 200);
  assert.equal(liquidated.body.status, 'dissolved');
  const repeated = await request('/api/businesses/B-1048/liquidate', { method: 'POST', body: {} });
  assert.equal(repeated.response.status, 409);
  const profile = await request('/api/businesses/B-1048');
  assert.equal(profile.body.business.status, 'dissolved');
});
