import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8917;
const base = `http://127.0.0.1:${port}`;
let server;

async function json(path, options) {
  const response = await fetch(`${base}${path}`, options);
  return { response, body: await response.json() };
}

before(async () => {
  server = spawn(process.execPath, ['server.js'], {
    cwd: new URL('..', import.meta.url),
    env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' },
    stdio: 'ignore',
  });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('public test server did not start');
});

after(() => server?.kill());

test('Tier 1 public API contract exposes stable, redacted read models', async () => {
  for (const path of ['/api/health', '/api/world', '/api/world/activity', '/api/rankings', '/api/cities', '/api/corporations']) {
    const { response, body } = await json(path);
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get('x-earth-api-version'), '2026-08');
    assert.equal(typeof body, 'object');
    assert.doesNotMatch(JSON.stringify(body), /password|password_hash|session_token|refresh_token/i);
  }
});

test('Tier 2 public landing page contains accessible navigation and required assets', async () => {
  for (const path of ['/', '/landing']) {
    const response = await fetch(`${base}${path}`);
    const html = await response.text();
    assert.equal(response.status, 200, path);
    assert.match(response.headers.get('content-type'), /text\/html/);
    assert.match(html, /<title>[^<]*EARTH/i);
    assert.match(html, /<h1[^>]*>[\s\S]+?<\/h1>/i);
    assert.match(html, /href=["'][^"']*prototype3\.html/i);
    assert.match(html, /id=["']theme["']/i);
    assert.match(html, /<nav|aria-label=/i);
  }
});

test('Tier 3 public activity and rankings remain deterministic and bounded', async () => {
  const first = await json('/api/world/activity');
  const second = await json('/api/world/activity');
  assert.deepEqual(first.body.activity, second.body.activity);
  assert.ok(first.body.activity.length <= 20);
  const rankings = await json('/api/rankings?limit=3');
  assert.ok(rankings.body.cities.length <= 3);
  assert.ok(rankings.body.corporations.length <= 3);
});

test('Tier 4 public API rejects mutation attempts on read-only endpoints', async () => {
  for (const path of ['/api/world', '/api/world/activity', '/api/rankings', '/api/cities', '/api/corporations']) {
    const { response } = await json(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    assert.ok([400, 401, 404, 405].includes(response.status), `${path} accepted a public mutation`);
  }
});

test('Tier 5 public browser journey reaches world navigation and public data', async () => {
  const html = await (await fetch(`${base}/`)).text();
  assert.match(html, /The world|WORLD/i);
  const world = await json('/api/world');
  assert.equal(world.body.institutions.ouc.kind, 'OUC');
  assert.ok(world.body.publicActivity || world.body.activity);
});
