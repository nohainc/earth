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
  assert.deepEqual(['material', 'components', 'energy', 'compute', 'food'].map(spotInstrumentSymbol), [
    'SPOT-MATERIAL', 'SPOT-COMPONENTS', 'SPOT-ENERGY', 'SPOT-COMPUTE', 'SPOT-FOOD',
  ]);
});

test('Market V2 derives instrument state from the authoritative book and fills', () => {
  const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
  const state = fs.readFileSync('cloudflare/src/market-state.ts', 'utf8');
  assert.match(schema, /CREATE TABLE market_instrument_state/);
  assert.match(state, /FROM market_orders/);
  assert.match(state, /FROM market_fills/);
  assert.match(fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8'), /rebuildMarketInstrumentState/);
  assert.match(fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8'), /refreshMarketCandles/);
  assert.match(fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8'), /instrument_type === 'SPOT'/);
  assert.match(fs.readFileSync('cloudflare/src/market-model.ts', 'utf8'), /instrument_type = 'SPOT'/);
  assert.equal(fs.existsSync('cloudflare/src/market-futures.ts'), false);
  assert.doesNotMatch(fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8'), /UPDATE market_prices SET [^;]*(supply|demand)/i);
  assert.equal(fs.existsSync('cloudflare/src/engines/market-engine.ts'), false);
});

test('Market V2 does not expose manual settlement endpoints', () => {
  const index = fs.readFileSync('cloudflare/src/index.ts', 'utf8');
  const simulator = fs.readFileSync('server.js', 'utf8');
  assert.doesNotMatch(index, /\/api\/market\/settle/);
  assert.doesNotMatch(simulator, /path === '\/api\/market\/settle'/);
  assert.match(fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8'), /settleMarketBatch/);
});

test('Market settlement timestamps use the closed batch boundary', () => {
  const source = fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8');
  const escrow = fs.readFileSync('cloudflare/src/market-escrow.ts', 'utf8');
  assert.match(source, /settleMarketBatch\([^)]*batchRowId/);
  assert.match(source, /const batchGameDay = Number\(currentBatch\.game_day\)/);
  assert.match(source, /const batchGameMinute = Number\(currentBatch\.game_minute\)/);
  assert.match(source, /marketBatchId\(\s*batchGameDay,\s*batchGameMinute,\s*MARKET_BATCH_GAME_MINUTES/);
  assert.match(source, /marketBatchRange\(absoluteBatchNumber, MARKET_BATCH_GAME_MINUTES\)/);
  assert.match(source, /gamePosition\(batchRange\.endMinute - 1\)/);
  assert.match(source, /postSettlementBatch\(tx, batchClosedAt\.gameDay, batchClosedAt\.gameMinute/);
  assert.doesNotMatch(escrow, /earth_post_settlement_batch\([^\n]*, 0,/);
});

test('Market settlement derives absolute batch time from coordinates, not row identity', () => {
  const rowId = 500;
  const absoluteBatch = marketBatchId(1, 60, MARKET_BATCH_GAME_MINUTES);
  const range = marketBatchRange(absoluteBatch, MARKET_BATCH_GAME_MINUTES);
  assert.equal(rowId === absoluteBatch, false);
  assert.deepEqual(gamePosition(range.endMinute - 1), { gameDay: 1, gameMinute: 119 });
});

test('Market fill sequence numbers are unique per instrument, not only per batch', () => {
  const migration = fs.readFileSync('db/migrations/137_market_fill_sequence_scope.sql', 'utf8');
  const source = fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8');
  assert.match(migration, /DROP CONSTRAINT IF EXISTS market_fills_batch_id_sequence_no_key/);
  assert.match(migration, /UNIQUE \(batch_id, instrument_id, sequence_no\)/);
  assert.match(source, /ON CONFLICT \(batch_id, instrument_id, sequence_no\) DO NOTHING/);
});

test('Market projections refresh only after the batch is completed', () => {
  const settlement = fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/market-scheduler.ts', 'utf8');
  const settlementBody = settlement.slice(settlement.indexOf('export async function settleMarketBatch'), settlement.indexOf('type EscrowEffect'));
  const completedAt = scheduler.indexOf("UPDATE market_batches SET status = 'COMPLETED'");
  const stateRefreshAt = scheduler.indexOf('rebuildMarketInstrumentState(repository');
  const candleRefreshAt = scheduler.indexOf('refreshMarketCandles(repository');
  assert.doesNotMatch(settlementBody, /refreshMarketPriceProjection|rebuildMarketInstrumentState/);
  assert.ok(completedAt >= 0);
  assert.ok(stateRefreshAt > completedAt);
  assert.ok(candleRefreshAt > completedAt);
});
