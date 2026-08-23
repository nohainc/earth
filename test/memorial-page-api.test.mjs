import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8921;
const base = `http://127.0.0.1:${port}`;
let server;

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('memorial test server did not start');
});
after(() => server?.kill());

async function get(path) {
  const response = await fetch(`${base}${path}`);
  return { response, body: await response.json() };
}

test('Tier 1 memorial API returns cemetery and pantheon public records without secrets', async () => {
  const cemetery = await get('/api/cemetery?limit=10');
  const pantheon = await get('/api/pantheon');
  assert.equal(cemetery.response.status, 200);
  assert.equal(pantheon.response.status, 200);
  assert.ok(cemetery.body.cemetery.length > 0);
  assert.ok(pantheon.body.deceasedPantheon.length > 0);
  assert.doesNotMatch(JSON.stringify({ cemetery, pantheon }), /password|password_hash|session_token/i);
});

test('Tier 2 memorial API supports case-insensitive search and dynasty filters', async () => {
  const search = await get('/api/cemetery?search=ROSTOV');
  const dynasty = await get('/api/cemetery?dynasty=vAnCe%20DyNaStY');
  assert.equal(search.body.cemetery[0].display_name, 'Elena Rostova');
  assert.equal(dynasty.body.cemetery[0].dynasty_name, 'Vance Dynasty');
});

test('Tier 3 memorial API bounds limits and returns deterministic records', async () => {
  const first = await get('/api/cemetery?limit=1');
  const second = await get('/api/cemetery?limit=1');
  assert.equal(first.body.cemetery.length, 1);
  assert.deepEqual(first.body.cemetery, second.body.cemetery);
  const bounded = await get('/api/cemetery?limit=9999');
  assert.ok(bounded.body.cemetery.length <= 100);
});

test('Tier 4 memorial read APIs reject mutation attempts', async () => {
  for (const path of ['/api/cemetery', '/api/pantheon']) {
    const response = await fetch(`${base}${path}`, { method: 'POST', headers: {'content-type': 'application/json'}, body: '{}' });
    assert.ok([400, 401, 404, 405].includes(response.status));
  }
});

test('Tier 5 memorial journey connects cemetery records to pantheon honors', async () => {
  const cemetery = await get('/api/cemetery?dynasty=Vance%20Dynasty');
  const pantheon = await get('/api/pantheon');
  assert.equal(cemetery.body.cemetery[0].successor_name, 'Amara Vance');
  assert.ok(pantheon.body.deceasedPantheon.some((entry) => entry.human_id === cemetery.body.cemetery[0].human_id));
});
