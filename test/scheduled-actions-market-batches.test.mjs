import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { eligibleMarketBatch } from '../cloudflare/src/market-scheduler.ts';

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
});
