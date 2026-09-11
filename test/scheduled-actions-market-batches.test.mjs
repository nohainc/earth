import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('scheduled actions use game-time leases and atomic claims', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/184_scheduled_actions_and_market_batches.sql'), 'utf8');
  const automation = fs.readFileSync(path.resolve('cloudflare/src/daily-automation.ts'), 'utf8');
  assert.match(migration, /lease_owner TEXT/);
  assert.match(migration, /lease_expires_at TIMESTAMPTZ/);
  assert.match(migration, /\(due_game_day, due_game_minute\) <= \(\$1, \$2\)/);
  assert.match(migration, /FOR UPDATE SKIP LOCKED/);
  assert.match(automation, /earth_claim_scheduled_actions/);
  assert.match(automation, /attempt_count >= 5/);
});

test('market execution is attached to persisted hourly batches', () => {
  const marketScheduler = fs.readFileSync(path.resolve('cloudflare/src/market-scheduler.ts'), 'utf8');
  const migration = fs.readFileSync(path.resolve('db/migrations/198_market_clearing_batches.sql'), 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS market_batches/);
  assert.match(migration, /PRIMARY KEY \(batch_id, instrument_id\)/);
  assert.match(marketScheduler, /processDueMarketBatches/);
  assert.match(marketScheduler, /batchId <= maxBatch/);
  assert.match(marketScheduler, /FROM market_batches/);
  assert.match(marketScheduler, /settleMarketBatch\(repository, instrument\.product, batchId, batchGameDay, instrument\.id\)/);
  assert.match(marketScheduler, /market_batch_instruments/);
});
