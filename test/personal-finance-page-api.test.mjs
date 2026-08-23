import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8931;
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

test('Tier 1 personal finance API protects private balances and mutations', async () => {
  const read = await fetch(`${base}/api/finance/personal`);
  const tax = await fetch(`${base}/api/taxes/settle`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ taxableAmount: 100 }) });
  const insolvency = await fetch(`${base}/api/finance/personal/declare`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
  assert.equal(read.status, 401);
  assert.equal(tax.status, 401);
  assert.equal(insolvency.status, 401);
});

test('Tier 2 personal finance API returns a redacted balance and solvency projection', async () => {
  const { response, body } = await request('/api/finance/personal');
  assert.equal(response.status, 200);
  assert.equal(body.account.owner_id, 'H-0044');
  assert.equal(body.state.protected_credits, 100);
  assert.ok(body.liquidatableAssets);
  assert.doesNotMatch(JSON.stringify(body), /password|session_token|password_hash/i);
});

test('Tier 3 personal finance API settles positive taxes exactly', async () => {
  const before = (await request('/api/finance/personal')).body.account.balance;
  const settled = await request('/api/taxes/settle', { method: 'POST', body: { taxableAmount: 1000 } });
  assert.equal(settled.response.status, 200);
  assert.equal(settled.body.settledAmount, 50);
  assert.equal(settled.body.remainingCredits, before - 50);
});

test('Tier 4 personal finance API rejects negative and non-finite tax amounts', async () => {
  const negative = await request('/api/taxes/settle', { method: 'POST', body: { taxableAmount: -100 } });
  assert.equal(negative.response.status, 400);
  const invalid = await request('/api/taxes/settle', { method: 'POST', body: { taxableAmount: 'not-a-number' } });
  assert.equal(invalid.response.status, 400);
});

test('Tier 5 personal finance API records insolvency once and preserves protected minimum', async () => {
  const declared = await request('/api/finance/personal/declare', { method: 'POST', body: { reason: 'QA restructuring' } });
  assert.equal(declared.response.status, 200);
  assert.equal(declared.body.protectedCredits, 100);
  const finance = await request('/api/finance/personal');
  assert.equal(finance.body.state.insolvency_status, 'restructured');
  const repeated = await request('/api/finance/personal/declare', { method: 'POST', body: {} });
  assert.equal(repeated.response.status, 409);
});
