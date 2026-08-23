import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8930;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie = '';
let initiativeId = '';

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

test('Tier 1 projects API protects personal initiatives and directory data', async () => {
  const initiatives = await fetch(`${base}/api/social/initiatives`);
  const directory = await fetch(`${base}/api/social/directory?q=ari`);
  assert.equal(initiatives.status, 401);
  assert.equal(directory.status, 401);
});

test('Tier 2 projects API returns scoped initiatives and searchable public partners', async () => {
  const initiatives = await request('/api/social/initiatives');
  const directory = await request('/api/social/directory?q=rostov');
  assert.equal(initiatives.response.status, 200);
  assert.ok(Array.isArray(initiatives.body.initiatives));
  assert.equal(directory.response.status, 200);
  assert.equal(directory.body.humans[0].id, 'H-0012');
  assert.doesNotMatch(JSON.stringify({ initiatives, directory }), /password|session_token|password_hash/i);
});

test('Tier 3 projects API creates and advances a collaborative initiative', async () => {
  const created = await request('/api/social/initiatives', { method: 'POST', body: { targetId: 'H-0012', kind: 'shared_project', title: 'QA Housing Project', body: 'Coordinate a housing improvement.', terms: { creditAmount: 20, deadlineGameDay: 20000, contributionTarget: 50 } } });
  assert.equal(created.response.status, 200);
  initiativeId = created.body.initiative.id;
  assert.equal(created.body.initiative.status, 'proposed');
  const contribution = await request(`/api/social/initiatives/${initiativeId}/contribute`, { method: 'POST', body: { contribution: 50 } });
  assert.equal(contribution.response.status, 200);
  assert.equal(contribution.body.initiative.status, 'completed');
  assert.equal(contribution.body.initiative.progress, 50);
});

test('Tier 4 projects API rejects invalid terms and unauthorized responses', async () => {
  const invalid = await request('/api/social/initiatives', { method: 'POST', body: { targetId: 'H-0012', kind: 'alliance', title: 'Bad', body: 'Bad', terms: { creditAmount: -1, deadlineGameDay: 1 } } });
  assert.equal(invalid.response.status, 400);
  const response = await request(`/api/social/initiatives/${initiativeId}/accept`, { method: 'POST', body: {} });
  assert.equal(response.response.status, 403);
  const invalidContribution = await request(`/api/social/initiatives/${initiativeId}/contribute`, { method: 'POST', body: { contribution: 101 } });
  assert.equal(invalidContribution.response.status, 400);
});

test('Tier 5 projects API preserves a stable refresh journey', async () => {
  const timeline = await request('/api/social/timeline?limit=20');
  const relationships = await request('/api/social/relationships');
  const initiatives = await request('/api/social/initiatives');
  assert.equal(timeline.response.status, 200);
  assert.equal(relationships.response.status, 200);
  assert.ok(initiatives.body.initiatives.some((initiative) => initiative.id === initiativeId));
});
