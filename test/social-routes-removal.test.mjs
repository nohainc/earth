import test, { after, before } from 'node:test';
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
  cookie = login.headers.get('set-cookie')?.split(';')[0] ?? '';
});
after(() => server?.kill());

test('retired social endpoints are gone while the successor directory remains', async () => {
  for (const path of ['/api/social/initiatives', '/api/social/relationships', '/api/social/timeline']) {
    assert.equal((await fetch(`${base}${path}`, { headers: { cookie } })).status, 404, path);
  }
  const directory = await fetch(`${base}/api/social/directory?q=rostov`, { headers: { cookie } });
  assert.equal(directory.status, 200);
  const body = await directory.json();
  for (const key of ['humans', 'businesses', 'cities', 'corporations', 'communities']) assert.ok(Array.isArray(body[key]));
  for (const key of ['initiatives', 'relationships', 'timeline']) assert.equal(key in body, false);
});
