import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8899;
let processHandle;
const request = async (path, options = {}) => {
  const headers = { accept: 'application/json', ...(options.headers || {}) };
  const response = await fetch(`http://127.0.0.1:${port}${path}`, { ...options, headers });
  const body = await response.json();
  return { status: response.status, body, headers: response.headers };
};

before(async () => {
  processHandle = spawn(process.execPath, ['server.js'], {
    cwd: new URL('..', import.meta.url),
    env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', DATABASE_URL: '' },
    stdio: 'ignore',
  });
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/health`);
      if (res.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error('server did not start');
});

after(() => processHandle?.kill());

test('health endpoint reports operational checks and request tracing', async () => {
  const result = await request('/api/health');
  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.ok(result.body.checks);
  assert.equal(result.body.authority, 'non-production');
  assert.equal(result.headers.get('x-earth-api-version'), '2026-08');
});

test('world activity exposes only public simulation signals', async () => {
  const result = await request('/api/world/activity');
  assert.equal(result.status, 200);
  assert.equal(result.body.activity.length, 3);
  assert.deepEqual(result.body.activity.map(event => event.type), ['world_clock', 'research_progress', 'market_cycle']);
  assert.ok(!JSON.stringify(result.body).includes('account-amara'));
});

test('world snapshot contains the EARTH core entities', async () => {
  const { status, body } = await request('/api/world');
  assert.equal(status, 200);
  assert.equal(body.human.id, 'H-0044');
  assert.equal(body.business.id, 'B-1048');
  assert.deepEqual(Object.keys(body.resources).sort(), ['components', 'compute', 'energy', 'food', 'material']);
  assert.equal(body.institutions.city.name, 'New Carthage');
  assert.equal(body.institutions.corporation.kind, 'CORPORATION');
});

test('market order settles at the canonical market price and writes a ledger entry', async () => {
  const orderPayload = { product: 'components', quantity: 12, limitPrice: 120, correlationId: 'order-retry-001' };
  const orderResponse = await request('/api/market/orders', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(orderPayload) });
  assert.equal(orderResponse.status, 200);
  const retryResponse = await request('/api/market/orders', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(orderPayload) });
  assert.equal(retryResponse.body.order.id, orderResponse.body.order.id);
  assert.equal(retryResponse.body.state.market.orders.length, 1);
  const settlement = await request('/api/market/settle', { method: 'POST' });
  assert.equal(settlement.body.result.fills.length, 1);
  assert.equal(settlement.body.result.fills[0].price, 118.7);
  assert.equal(settlement.body.state.ledgerEntries.length, 1);
  assert.equal(settlement.body.state.market.orders[0].status, 'filled');
  assert.equal(settlement.body.state.resources.components, 98);
});

test('governance rejects a duplicate ballot', async () => {
  const first = await request('/api/governance/proposals/042/vote', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ vote: 'support' }) });
  assert.equal(first.status, 200);
  const duplicate = await request('/api/governance/proposals/042/vote', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ vote: 'oppose' }) });
  assert.equal(duplicate.status, 400);
  assert.match(duplicate.body.error, /already recorded/);
});

test('day advancement applies business output and advances the clock', async () => {
  const beforeState = await request('/api/world');
  const result = await request('/api/day/advance', { method: 'POST' });
  assert.equal(result.body.result.day, beforeState.body.clock.day + 1);
  assert.ok(result.body.state.human.credits > beforeState.body.human.credits);
  assert.ok(result.body.state.business.condition < beforeState.body.business.condition);
});

test('successor registration is explicit and auditable in world state', async () => {
  const result = await request('/api/life/successor', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Mira Kline' }) });
  assert.equal(result.status, 200);
  assert.equal(result.body.life.successor.name, 'Mira Kline');
  assert.equal(result.body.life.successor.registeredOnDay, result.body.state.clock.day);
});

test('event stream is available for live client invalidation', async () => {
  const response = await fetch(`http://127.0.0.1:${port}/api/events`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/event-stream/);
  await response.body.cancel();
});

test('audit endpoint confirms core world invariants', async () => {
  const { status, body } = await request('/api/audit');
  assert.equal(status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.checks.ordersValid, true);
  assert.equal(body.checks.ledgerValid, true);
  assert.equal(body.checks.balancesValid, true);
  assert.equal(body.checks.ballotUniqueness, true);
});

test('public landing page and game client are served from the same entrypoint', async () => {
  const landing = await fetch(`http://127.0.0.1:${port}/`);
  const landingHtml = await landing.text();
  assert.equal(landing.status, 200);
  assert.match(landing.headers.get('content-type'), /text\/html/);
  assert.match(landingHtml, /Build a future/);
  assert.match(landingHtml, /prototype3\.html/);
  const game = await fetch(`http://127.0.0.1:${port}/prototype3.html`);
  assert.equal(game.status, 200);
  assert.match(await game.text(), /The world is moving/);
});

test('new user-facing product copy uses UC terminology', async () => {
  const landingHtml = await (await fetch(`http://127.0.0.1:${port}/`)).text();
  const prototypeHtml = await (await fetch(`http://127.0.0.1:${port}/prototype3.html`)).text();
  assert.match(landingHtml, /A UC WORLD/);
  assert.match(landingHtml, />UC</);
  assert.match(prototypeHtml, /UNITED CORPORATIONS|A UC WORLD/);
  assert.doesNotMatch(landingHtml, /AN OUC WORLD|THE OUC WORLD|>OUC</);
  assert.doesNotMatch(prototypeHtml, /AN OUC WORLD|OUC \/ CENTRAL MARKET/);
});

test('authentication flow supports register, login, session lookup, and logout', async () => {
  // 1. Unauthenticated /api/auth/me returns authenticated: false
  const unauthMe = await request('/api/auth/me');
  assert.equal(unauthMe.status, 200);
  assert.equal(unauthMe.body.authenticated, false);
  assert.equal(unauthMe.body.human, null);

  // 2. Register a new user
  const regPayload = {
    email: 'newuser@earthuc.com',
    password: 'Password123456',
    passwordConfirmation: 'Password123456',
    displayName: 'Test Human',
  };
  const regRes = await request('/api/auth/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(regPayload),
  });
  assert.equal(regRes.status, 201);
  assert.equal(regRes.body.ok, true);
  assert.equal(regRes.body.human.email, 'newuser@earthuc.com');
  const cookie = regRes.headers.get('set-cookie') || (regRes.headers.getSetCookie && regRes.headers.getSetCookie().join('; ')) || '';
  assert.ok(cookie);

  // 3. Authenticated session lookup via cookie
  const authMe = await request('/api/auth/me', {
    headers: { cookie },
  });
  assert.equal(authMe.status, 200);
  assert.equal(authMe.body.authenticated, true);
  assert.equal(authMe.body.human.email, 'newuser@earthuc.com');
  assert.equal(authMe.body.human.id, regRes.body.human.id);

  // 4. Duplicate registration returns 409 CONFLICT
  const dupReg = await request('/api/auth/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(regPayload),
  });
  assert.equal(dupReg.status, 409);
  assert.equal(dupReg.body.code, 'CONFLICT');

  // 5. Login with invalid password returns 401 AUTHENTICATION_REQUIRED
  const badLogin = await request('/api/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'newuser@earthuc.com', password: 'wrongpassword' }),
  });
  assert.equal(badLogin.status, 401);
  assert.equal(badLogin.body.code, 'AUTHENTICATION_REQUIRED');

  // 6. Login with valid password returns 200
  const goodLogin = await request('/api/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'newuser@earthuc.com', password: 'Password123456' }),
  });
  assert.equal(goodLogin.status, 200);
  assert.equal(goodLogin.body.ok, true);
  assert.equal(goodLogin.body.human.email, 'newuser@earthuc.com');

  // 7. Logout clears session
  const logoutRes = await request('/api/auth/logout', {
    method: 'POST',
    headers: { cookie },
  });
  assert.equal(logoutRes.status, 200);
  assert.equal(logoutRes.body.ok, true);
});

test('authenticated session response uses the public human projection only', async () => {
  const login = await request('/api/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'amara@earthuc.com', password: 'password123456' }),
  });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie') || (login.headers.getSetCookie && login.headers.getSetCookie().join('; ')) || '';
  assert.ok(cookie);

  const me = await request('/api/auth/me', { headers: { cookie } });
  assert.equal(me.status, 200);
  assert.equal(me.body.authenticated, true);
  assert.equal(me.body.human.id, 'H-0044');
  assert.equal(me.body.human.email, 'amara@earthuc.com');
  assert.equal(me.body.human.passwordHash, undefined);
  assert.equal(me.body.sessionToken, undefined);
});

test('live event stream and JSON endpoints support event replay after reconnect', async () => {
  // Advance day to trigger published events
  await request('/api/day/advance', { method: 'POST' });
  await request('/api/life/successor', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Replay Test Successor' }) });

  // Query events JSON with cursor / after
  const jsonEvents = await request('/api/events?limit=10');
  assert.equal(jsonEvents.status, 200);
  assert.ok(jsonEvents.body.events.length > 0);
  const firstEventId = jsonEvents.body.events[0].id;

  // Replay events after firstEventId
  const replayed = await request(`/api/events?after=${firstEventId}`);
  assert.equal(replayed.status, 200);
  assert.ok(replayed.body.events.every((e) => e.id > firstEventId));
});

test('API error responses follow the standard production error envelope and status codes', async () => {
  // 1. Malformed JSON returns 400 VALIDATION_ERROR with correlationId
  const malformed = await request('/api/market/orders', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-request-id': 'req-test-uuid-123' },
    body: '{ malformed json payload',
  });
  assert.equal(malformed.status, 400);
  assert.equal(malformed.body.ok, false);
  assert.equal(malformed.body.code, 'VALIDATION_ERROR');
  assert.equal(malformed.body.correlationId, 'req-test-uuid-123');

  // 2. Route not found returns 404 NOT_FOUND with correlationId
  const notFound = await request('/api/non-existent-endpoint');
  assert.equal(notFound.status, 404);
  assert.equal(notFound.body.ok, false);
  assert.equal(notFound.body.code, 'NOT_FOUND');
  assert.ok(notFound.body.correlationId);

  // 3. No stack traces, SQL, or passwords returned in errors
  assert.equal(typeof notFound.body.error, 'string');
  assert.doesNotMatch(notFound.body.error, /SELECT|INSERT|UPDATE|password_hash|at Server\./i);
});
