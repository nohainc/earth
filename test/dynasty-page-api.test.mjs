import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8920;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie;

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, { ...options, headers: { accept: 'application/json', ...(cookie ? { cookie } : {}), ...(options.headers || {}) } });
  return { response, body: await response.json() };
}

before(async () => {
  server = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' }, stdio: 'ignore' });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try { if ((await fetch(`${base}/api/health`)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('dynasty test server did not start');
});
after(() => server?.kill());

test('Tier 1 dynasty API returns lineage, perks, heirlooms, and redacted data', async () => {
  const { response, body } = await request('/api/dynasty');
  assert.equal(response.status, 200);
  assert.equal(body.dynasty.dynasty_name, 'House Vance');
  assert.ok(Array.isArray(body.lineage));
  assert.ok(Array.isArray(body.heirlooms));
  assert.doesNotMatch(JSON.stringify(body), /password|password_hash|session_token/i);
});

test('Tier 2 dynasty mutations require authentication', async () => {
  const result = await request('/api/dynasty/motto', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({ motto: 'A valid creed' }) });
  assert.equal(result.response.status, 401);
});

test('Tier 3 authenticated dynasty actions unlock perks and toggle heirlooms', async () => {
  const login = await request('/api/auth/login', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({email: 'amara@earthuc.com', password: 'password123456'}) });
  cookie = login.response.headers.get('set-cookie')?.split(';')[0];
  assert.ok(cookie);
  const perk = await request('/api/dynasty/perks/unlock', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({perkKey: 'diplomatic_dynasty'}) });
  assert.equal(perk.response.status, 200, JSON.stringify(perk.body));
  const equipped = await request('/api/dynasty/heirlooms/equip', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({heirloomId: 'HLM-001'}) });
  assert.equal(equipped.response.status, 200);
  assert.equal(equipped.body.isEquipped, false);
});

test('Tier 4 dynasty API validates motto and heirloom inputs', async () => {
  const motto = await request('/api/dynasty/motto', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({ motto: 'x', dynastyName: 'House Vance' }) });
  assert.equal(motto.response.status, 400);
  const heirloom = await request('/api/dynasty/heirlooms/forge', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({ name: 'x' }) });
  assert.equal(heirloom.response.status, 400);
});

test('Tier 5 dynasty page journey updates creed and reloads overview', async () => {
  const updated = await request('/api/dynasty/motto', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({ motto: 'From memory we build', dynastyName: 'House Vance Neo' }) });
  assert.equal(updated.response.status, 200, JSON.stringify(updated.body));
  const overview = await request('/api/dynasty');
  assert.equal(overview.body.dynasty.motto, 'From memory we build');
  assert.equal(overview.body.dynasty.dynasty_name, 'House Vance Neo');
});
