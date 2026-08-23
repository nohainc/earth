import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 8928;
const base = `http://127.0.0.1:${port}`;
let server;
let cookie = '';
let orderId = '';

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

test('Tier 1 trade API protects private order mutations', async () => {
  const response = await fetch(`${base}/api/market/orders`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ product: 'energy', quantity: 1, limitPrice: 1 }) });
  assert.equal(response.status, 401);
});

test('Tier 2 trade API exposes bounded market history and safe order book data', async () => {
  const history = await request('/api/market/history?product=energy&days=7');
  const book = await request('/api/market/book');
  assert.equal(history.response.status, 200);
  assert.equal(history.body.product, 'energy');
  assert.ok(history.body.history.length <= 7);
  assert.equal(book.response.status, 200);
  assert.equal(typeof book.body.feeRate, 'number');
  assert.doesNotMatch(JSON.stringify({ history, book }), /password|session_token|password_hash/i);
});

test('Tier 3 trade API places and settles a buy order at the clearing price', async () => {
  const placed = await request('/api/market/orders', { method: 'POST', body: { product: 'components', side: 'buy', quantity: 2, limitPrice: 120 } });
  assert.equal(placed.response.status, 200);
  orderId = placed.body.order.id;
  assert.equal(placed.body.order.side, 'buy');
  const settled = await request('/api/market/settle', { method: 'POST', body: { product: 'components' } });
  assert.equal(settled.response.status, 200);
  assert.equal(settled.body.result.fills[0].price, 118.7);
  assert.equal(settled.body.state.market.orders.find((order) => order.id === orderId).status, 'filled');
});

test('Tier 4 trade API validates side, inventory, and quantity boundaries', async () => {
  const side = await request('/api/market/orders', { method: 'POST', body: { product: 'energy', side: 'barter', quantity: 1, limitPrice: 1 } });
  assert.equal(side.response.status, 400);
  const inventory = await request('/api/market/orders', { method: 'POST', body: { product: 'energy', side: 'sell', quantity: 9999, limitPrice: 1 } });
  assert.equal(inventory.response.status, 400);
  const quantity = await request('/api/market/orders', { method: 'POST', body: { product: 'energy', side: 'buy', quantity: 1.5, limitPrice: 1 } });
  assert.equal(quantity.response.status, 400);
});

test('Tier 5 trade API supports sell settlement and owned-order cancellation refunds', async () => {
  const sold = await request('/api/market/orders', { method: 'POST', body: { product: 'energy', side: 'sell', quantity: 2, limitPrice: 0.5 } });
  assert.equal(sold.response.status, 200);
  const settled = await request('/api/market/settle', { method: 'POST', body: { product: 'energy' } });
  assert.equal(settled.response.status, 200);
  assert.equal(settled.body.state.market.orders.find((order) => order.id === sold.body.order.id).status, 'filled');
  const pending = await request('/api/market/orders', { method: 'POST', body: { product: 'energy', side: 'sell', quantity: 1, limitPrice: 0.5 } });
  const cancelled = await request(`/api/market/orders/${pending.body.order.id}`, { method: 'DELETE' });
  assert.equal(cancelled.response.status, 200);
  assert.equal(cancelled.body.status, 'cancelled');
  const repeated = await request(`/api/market/orders/${pending.body.order.id}`, { method: 'DELETE' });
  assert.equal(repeated.response.status, 409);
});
