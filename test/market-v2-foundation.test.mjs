import test from 'node:test';
import assert from 'node:assert/strict';
import { absoluteGameMinute, gamePosition, marketBatchId, marketBatchRange } from '../cloudflare/src/market-time.ts';
import { MARKET_ASSET_IDS, MARKET_BATCH_GAME_MINUTES, spotInstrumentSymbol } from '../cloudflare/src/market-model.ts';
import fs from 'node:fs';

test('Market V2 uses unambiguous game-time coordinates', () => {
  assert.equal(absoluteGameMinute(1, 0), 0);
  assert.equal(absoluteGameMinute(2, 0), 1440);
  assert.deepEqual(gamePosition(1440), { gameDay: 2, gameMinute: 0 });
  assert.equal(marketBatchId(1, 59, MARKET_BATCH_GAME_MINUTES), 0);
  assert.equal(marketBatchId(1, 60, MARKET_BATCH_GAME_MINUTES), 1);
  assert.deepEqual(marketBatchRange(1, MARKET_BATCH_GAME_MINUTES), { startMinute: 60, endMinute: 120 });
});

test('Market V2 keeps the canonical six-asset IDs and instrument symbols', () => {
  assert.deepEqual(MARKET_ASSET_IDS, { CREDIT: 1, MATERIAL: 2, COMPONENTS: 3, ENERGY: 4, COMPUTE: 5, FOOD: 6 });
  assert.equal(spotInstrumentSymbol('material'), 'SPOT-MATERIAL');
});

test('Market V2 derives instrument state from the authoritative book and fills', () => {
  const migration = fs.readFileSync('db/migrations/201_market_instrument_state.sql', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS market_instrument_state/);
  assert.match(migration, /earth_rebuild_market_instrument_state/);
  assert.match(migration, /FROM market_orders/);
  assert.match(migration, /FROM market_fills/);
  assert.match(fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8'), /rebuildMarketInstrumentState/);
  assert.match(fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8'), /refreshMarketCandles/);
  const futures = fs.readFileSync('cloudflare/src/market-futures.ts', 'utf8');
  assert.match(futures, /DELIVERY_FUTURE/);
  assert.match(futures, /submitMarketOrder/);
  assert.match(futures, /instrumentId/);
  assert.doesNotMatch(fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8'), /UPDATE market_prices SET [^;]*(supply|demand)/i);
  assert.equal(fs.existsSync('cloudflare/src/engines/market-engine.ts'), false);
});

test('Market V2 does not expose manual settlement endpoints', () => {
  const index = fs.readFileSync('cloudflare/src/index.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/market-routes.ts', 'utf8');
  const simulator = fs.readFileSync('server.js', 'utf8');
  assert.doesNotMatch(index, /\/api\/market\/settle/);
  assert.doesNotMatch(routes, /\/api\/market\/settle/);
  assert.doesNotMatch(simulator, /path === '\/api\/market\/settle'/);
  assert.match(fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8'), /settleMarketBatch/);
});
