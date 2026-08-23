import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8922;
const base = `http://127.0.0.1:${port}`;
let server;

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('archive test server did not start');
});
after(() => server?.kill());

async function get(path) {
  const response = await fetch(`${base}${path}`);
  return { response, body: await response.json() };
}

test('Tier 1 archive API returns public world history and safe record shape', async () => {
  const { response, body } = await get('/api/history?limit=10');
  assert.equal(response.status, 200);
  assert.ok(Array.isArray(body.events));
  assert.ok(body.persistence);
  assert.doesNotMatch(JSON.stringify(body), /password|password_hash|session_token|secret/i);
});

test('Tier 2 archive API respects bounded limits', async () => {
  const small = await get('/api/history?limit=1');
  const huge = await get('/api/history?limit=9999');
  assert.ok(small.body.events.length <= 1);
  assert.ok(huge.body.events.length <= 100);
});

test('Tier 3 archive API is deterministic and preserves event ordering', async () => {
  const first = await get('/api/history?limit=10');
  const second = await get('/api/history?limit=10');
  assert.deepEqual(first.body.events, second.body.events);
  for (let i = 1; i < first.body.events.length; i += 1) {
    assert.ok(first.body.events[i].gameDay >= first.body.events[i - 1].gameDay);
  }
});

test('Tier 4 archive API rejects writes and deletes', async () => {
  for (const method of ['POST', 'DELETE']) {
    const response = await fetch(`${base}/api/history`, { method, headers: {'content-type': 'application/json'}, body: '{}' });
    assert.ok([400, 401, 404, 405].includes(response.status));
  }
});

test('Tier 5 archive journey links history to the world snapshot', async () => {
  const history = await get('/api/history?limit=10');
  const world = await get('/api/world');
  const activity = await get('/api/world/activity');
  assert.equal(world.response.status, 200);
  assert.ok(Array.isArray(history.body.events));
  assert.ok(Array.isArray(activity.body.activity));
  if (history.body.events.length > 0 && activity.body.activity.length > 0) {
    assert.equal(history.body.events[0].type, activity.body.activity[0].type);
  }
});
