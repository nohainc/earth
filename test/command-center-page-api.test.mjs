import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8923;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie;

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('command center test server did not start');
});
after(() => server?.kill());

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, { ...options, headers: { accept: 'application/json', ...(cookie ? { cookie } : {}), ...(options.headers || {}) } });
  return { response, body: await response.json() };
}

test('Tier 1 command center API protects the personalized briefing', async () => {
  const result = await request('/api/player/daily-briefing');
  assert.equal(result.response.status, 401);
});

test('Tier 2 command center briefing returns bounded market, civic, and business signals', async () => {
  const login = await request('/api/auth/login', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({email: 'amara@earthuc.com', password: 'password123456'}) });
  cookie = login.response.headers.get('set-cookie')?.split(';')[0];
  const result = await request('/api/player/daily-briefing');
  assert.equal(result.response.status, 200);
  assert.ok(result.body.marketMovements.length <= 12);
  assert.ok(result.body.businessSummary);
  assert.ok(result.body.civicSummary);
  assert.doesNotMatch(JSON.stringify(result.body), /password|session_token|password_hash/i);
});

test('Tier 3 command center world model exposes deterministic queues and objectives', async () => {
  const first = await request('/api/world');
  const second = await request('/api/world');
  assert.deepEqual(first.body.objectives, second.body.objectives);
  assert.ok(Array.isArray(first.body.decisionQueue));
  assert.ok(first.body.objectives.length <= 20);
});

test('Tier 4 command center read models reject mutation attempts', async () => {
  for (const path of ['/api/player/daily-briefing', '/api/world']) {
    const result = await request(path, { method: 'POST', headers: {'content-type': 'application/json'}, body: '{}' });
    assert.ok([400, 401, 404, 405].includes(result.response.status));
  }
});

test('Tier 5 command center journey links briefing day to world clock', async () => {
  const briefing = await request('/api/player/daily-briefing');
  const world = await request('/api/world');
  assert.equal(briefing.body.gameDay, world.body.clock.day);
  assert.ok(briefing.body.unreadAlerts);
});
