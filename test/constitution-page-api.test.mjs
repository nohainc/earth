import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8934;
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

test('Tier 1 Constitution API protects constitutional mutations', async () => {
  const result = await request('/api/governance/proposals/042/vote', { method: 'POST', body: { vote: 'support', weight: 999999 } }, false);
  assert.equal(result.response.status, 401);
});

test('Tier 2 Constitution read model exposes governance state without secrets', async () => {
  const result = await request('/api/world', {}, false);
  assert.equal(result.response.status, 200);
  assert.ok(Array.isArray(result.body.governance.proposals));
  assert.equal(result.body.governance.proposals[0].id, '042');
  assert.doesNotMatch(JSON.stringify(result.body), /password|session_token|password_hash/i);
});

test('Tier 3 Constitution API records an authenticated ballot', async () => {
  const result = await request('/api/governance/proposals/042/vote', { method: 'POST', body: { vote: 'support', weight: 999999, humanId: 'H-9999' } });
  assert.equal(result.response.status, 200);
  assert.equal(result.body.ok, true);
  assert.equal(result.body.proposal.ballots['H-0044'], 'support');
  assert.notEqual(result.body.proposal.votes.support, 999999);
});

test('Tier 4 Constitution API rejects invalid votes and unknown proposals', async () => {
  const invalid = await request('/api/governance/proposals/042/vote', { method: 'POST', body: { vote: 'invalid' } });
  assert.equal(invalid.response.status, 400);
  const unknown = await request('/api/governance/proposals/UNKNOWN/vote', { method: 'POST', body: { vote: 'support' } });
  assert.equal(unknown.response.status, 404);
});

test('Tier 5 Constitution API prevents duplicate constitutional ballots', async () => {
  const repeated = await request('/api/governance/proposals/042/vote', { method: 'POST', body: { vote: 'oppose' } });
  assert.equal(repeated.response.status, 400);
  assert.match(repeated.body.error, /already recorded/i);
});
