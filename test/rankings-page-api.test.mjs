import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8918;
const base = `http://127.0.0.1:${port}`;
let server;

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('rankings test server did not start');
});
after(() => server?.kill());

async function get(query) {
  const response = await fetch(`${base}/api/rankings${query}`);
  return { response, body: await response.json() };
}

test('Tier 1 rankings API returns all public categories with stable fields', async () => {
  const { response, body } = await get('?limit=5');
  assert.equal(response.status, 200);
  for (const key of ['citizens', 'cities', 'corporations', 'dynasticHouses', 'technologies']) {
    assert.ok(Array.isArray(body[key]), key);
    assert.ok(body[key].length <= 5, key);
  }
  assert.equal(body.citizens[0].rank, 1);
  assert.equal(body.citizens[0].displayName, 'Amara Vance');
});

test('Tier 2 rankings API supports category, metric, search, and offset', async () => {
  const { body } = await get('?category=corporations&metric=marketCap&search=aegis&limit=1&offset=0');
  assert.equal(body.category, 'corporations');
  assert.equal(body.metric, 'marketcap');
  assert.equal(body.corporations[0].name, 'Aegis Fusion & Grid');
  assert.doesNotMatch(JSON.stringify(body), /password|session_token|password_hash/i);
});

test('Tier 3 rankings API offset paginates deterministically', async () => {
  const first = await get('?category=cities&limit=1&offset=0');
  const second = await get('?category=cities&limit=1&offset=1');
  assert.equal(first.body.cities[0].name, 'Neo-Tokyo');
  assert.equal(second.body.cities[0].name, 'New York');
});

test('Tier 4 rankings API rejects mutations', async () => {
  const response = await fetch(`${base}/api/rankings`, { method: 'POST', headers: {'content-type': 'application/json'}, body: '{}' });
  assert.ok([400, 401, 404, 405].includes(response.status));
});

test('Tier 5 rankings API remains a public read journey', async () => {
  const { response, body } = await get('?category=technologies&limit=3');
  assert.equal(response.status, 200);
  assert.equal(body.technologies[0].name, 'Quantum Core Infrastructure');
  assert.equal(body.generatedFrom, 'reference-simulator');
});
