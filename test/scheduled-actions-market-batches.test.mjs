import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { eligibleMarketBatch, marketBatchGameDay, marketBatchThroughClosedDay } from '../cloudflare/src/market-scheduler.ts';

const read = (path) => fs.readFileSync(path, 'utf8');

test('market processing uses an independent absolute-time watermark', () => {
  const migration = read('db/migrations/133_absolute_market_processing_watermark.sql');
  const scheduler = read('cloudflare/src/market-scheduler.ts');
  const worldScheduler = read('cloudflare/src/scheduler-postgres.ts');

  assert.match(migration, /market_processing_control/);
  assert.match(migration, /processed_through_market_batch BIGINT/);
  assert.match(scheduler, /readAuthoritativeGameTime/);
  assert.match(scheduler, /eligibleMarketBatch/);
  assert.match(scheduler, /processed_through_market_batch/);
  assert.match(scheduler, /nextBatch = Number\(control\.processed_through_market_batch\) \+ 1/);
  assert.match(worldScheduler, /processDueMarketBatches/);
  assert.doesNotMatch(scheduler, /settledThroughGameDay/);
});

test('market catch-up processes closed batches and leaves the partial batch open', () => {
  const scheduler = read('cloudflare/src/market-scheduler.ts');
  assert.match(scheduler, /Math\.floor\(Math\.max\(0, totalGameMinutes\) \/ MARKET_BATCH_GAME_MINUTES\) - 1/);
  assert.match(scheduler, /while \(Date\.now\(\) - startedAt < workBudgetMs\)/);
  assert.match(scheduler, /processedThroughMarketBatch/);
  assert.equal(eligibleMarketBatch(0), -1);
  assert.equal(eligibleMarketBatch(59), -1);
  assert.equal(eligibleMarketBatch(60), 0);
  assert.equal(eligibleMarketBatch(10000), 165);
  assert.equal(marketBatchThroughClosedDay(0), -1);
  assert.equal(marketBatchThroughClosedDay(1), 23);
  assert.equal(marketBatchThroughClosedDay(20), 479);
  assert.equal(marketBatchGameDay(0), 1);
  assert.equal(marketBatchGameDay(23), 1);
  assert.equal(marketBatchGameDay(24), 2);
});

test('daily catch-up drains each day market interval before settling that day', () => {
  const worldScheduler = read('cloudflare/src/scheduler-postgres.ts');
  assert.match(worldScheduler, /marketBatchThroughClosedDay\(nextDay\)/);
  assert.match(worldScheduler, /processDueMarketBatches\([\s\S]*?nextDay,[\s\S]*?runResumableSettlementDay/);
  assert.match(worldScheduler, /processedThroughMarketBatch < marketTargetBatch/);
  assert.match(worldScheduler, /currentSettled >= targetDay \? undefined : currentSettled/);
});

test('standing orders participate in later market batches', () => {
  const market = read('cloudflare/src/market-postgres.ts');
  const scheduler = read('cloudflare/src/market-scheduler.ts');
  assert.match(scheduler, /INSERT INTO market_batches/);
  assert.match(market, /JOIN market_batches origin ON origin\.id = o\.batch_id/);
  assert.match(market, /origin\.game_day < \$2 OR \(origin\.game_day = \$2 AND origin\.game_minute <= \$3\)/);
  assert.doesNotMatch(market, /WHERE batch_id = \$1 AND instrument_id = \$2 AND status IN/);
});

test('market expiry is evaluated inside historical batch replay', () => {
  const scheduler = read('cloudflare/src/market-scheduler.ts');
  assert.doesNotMatch(scheduler, /expireMarketOrders\(repository, clock\.gameDay/);
  assert.match(scheduler, /const batchGameDay = marketBatchGameDay\(batchNumber\)/);
  assert.match(scheduler, /expireMarketOrders\(repository, batchGameDay, .*100\)/);
});
