import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8925;
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

test('Tier 1 notifications API requires authentication for personal alerts', async () => {
  const response = await fetch(`${base}/api/notifications?limit=10`);
  assert.equal(response.status, 401);
  const mutation = await fetch(`${base}/api/notifications/read-all`, { method: 'POST' });
  assert.equal(mutation.status, 401);
});

test('Tier 2 notifications API returns bounded, redacted notification records', async () => {
  const { response, body } = await request('/api/notifications?limit=1');
  assert.equal(response.status, 200);
  assert.equal(body.notifications.length, 1);
  assert.equal(body.limit, 1);
  assert.equal(body.unread, 1);
  assert.doesNotMatch(JSON.stringify(body), /password|session_token|password_hash/i);
});

test('Tier 3 notifications API marks one alert read and updates unread counts', async () => {
  const { response, body } = await request('/api/notifications/NOTIF-001/read', { method: 'POST' });
  assert.equal(response.status, 200);
  assert.equal(body.unreadCount, 0);
  const listed = await request('/api/notifications');
  assert.equal(listed.body.notifications[0].read, true);
});

test('Tier 4 notifications API rejects unknown notification mutations', async () => {
  const { response, body } = await request('/api/notifications/NOTIF-NOT-OWNED/read', { method: 'POST' });
  assert.equal(response.status, 404);
  assert.equal(body.code, 'NOT_FOUND');
});

test('Tier 5 notifications API supports idempotent mark-all-read journey', async () => {
  const first = await request('/api/notifications/read-all', { method: 'POST' });
  const second = await request('/api/notifications/read-all', { method: 'POST' });
  assert.equal(first.body.unreadCount, 0);
  assert.equal(second.body.unreadCount, 0);
  const listed = await request('/api/notifications?limit=20');
  assert.ok(listed.body.notifications.every((notification) => notification.read === true));
});
