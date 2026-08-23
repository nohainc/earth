import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8924;
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

test('Tier 1 messages API protects personal dispatches', async () => {
  const response = await fetch(`${base}/api/comm/dispatches?folder=inbox`);
  assert.equal(response.status, 401);
  const channels = await fetch(`${base}/api/comm/channels`);
  assert.equal(channels.status, 200);
});

test('Tier 2 messages API returns safe filtered inbox data', async () => {
  const { response, body } = await request('/api/comm/dispatches?folder=inbox&limit=1&offset=0');
  assert.equal(response.status, 200);
  assert.equal(body.dispatches.length, 1);
  assert.equal(body.total, 2);
  assert.equal(body.limit, 1);
  assert.equal(body.offset, 0);
  assert.doesNotMatch(JSON.stringify(body), /password_hash|session_token/i);
});

test('Tier 3 messages API sends, reads, and archives deterministically', async () => {
  const sent = await request('/api/comm/dispatches', { method: 'POST', body: { recipientId: 'H-0012', subject: 'QA dispatch', body: 'Test transmission' } });
  assert.equal(sent.response.status, 200);
  const id = sent.body.dispatch.id;
  assert.equal(sent.body.dispatch.sender_human_id, 'H-0044');
  const read = await request('/api/comm/dispatches/read', { method: 'POST', body: { dispatchId: 'mail-1' } });
  assert.equal(read.body.read, true);
  const archived = await request('/api/comm/dispatches/archive', { method: 'POST', body: { dispatchId: 'mail-1' } });
  assert.equal(archived.body.archived, true);
  const inbox = await request('/api/comm/dispatches?folder=inbox');
  assert.ok(!inbox.body.dispatches.some((item) => item.id === 'mail-1'));
  const outgoing = await request('/api/comm/dispatches?folder=sent');
  assert.ok(outgoing.body.dispatches.some((item) => item.id === id));
});

test('Tier 4 messages API rejects invalid and unauthorized mutations', async () => {
  const invalid = await request('/api/comm/dispatches', { method: 'POST', body: { recipientId: 'H-0012' } });
  assert.equal(invalid.response.status, 400);
  const unauthorized = await fetch(`${base}/api/comm/dispatches/archive`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ dispatchId: 'mail-2' }) });
  assert.equal(unauthorized.status, 401);
});

test('Tier 5 messages API publishes live channel messages and metrics', async () => {
  const sent = await request('/api/comm/messages', { method: 'POST', body: { channelId: 'channel-global-relay', body: 'Live QA signal' } });
  assert.equal(sent.response.status, 200);
  const messages = await request('/api/comm/messages?channelId=channel-global-relay&limit=1');
  assert.equal(messages.body.messages.at(-1).body, 'Live QA signal');
  const metrics = await request('/api/comm/metrics');
  assert.equal(metrics.response.status, 200);
  assert.equal(typeof metrics.body.unreadDispatches, 'number');
});
