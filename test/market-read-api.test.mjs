import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/market-api.ts', import.meta.url), 'utf8');
const index = fs.readFileSync(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');

test('market read API exposes the unified V2 resources', () => {
  for (const route of [
    '/api/market/instruments',
    '/api/market/orders/my',
    '/api/market/orders/',
    'book|batches|fills|candles',
  ]) assert.match(source, new RegExp(route.replaceAll('/', '\\/')));
  for (const table of ['market_instruments', 'market_orders', 'market_batches', 'market_fills', 'market_candles']) {
    assert.match(source, new RegExp(table));
  }
  assert.match(source, /quantity_units/);
  assert.match(source, /priceUnitsToDisplayPrice/);
  assert.doesNotMatch(source, /market_trades|commodity_futures_contracts|account_balances|resource_balances/);
});

test('production request path invokes the unified market API handler', () => {
  assert.match(index, /import \{ handleMarketApiRoutes \} from '\.\/market-api\.ts'/);
  assert.match(index, /handleMarketApiRoutes\(request, env, url\)/);
});
