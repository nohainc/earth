import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8899;
let processHandle;
const request = async (path, options) => {
  const response = await fetch(`http://127.0.0.1:${port}${path}`, options);
  const body = await response.json();
  return { status: response.status, body, headers: response.headers };
};

before(async () => {
  processHandle = spawn(process.execPath, ['server.js'], { cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port) } });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('server did not start')), 5000);
    processHandle.stdout.on('data', data => { if (String(data).includes('listening')) { clearTimeout(timer); resolve(); } });
    processHandle.on('error', reject);
  });
});

after(() => processHandle?.kill());

test('health endpoint reports operational checks and request tracing', async () => {
  const result = await request('/api/health');
  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.ok(result.body.checks);
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
  assert.deepEqual(Object.keys(body.resources).sort(), ['components', 'compute', 'energy', 'material']);
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
