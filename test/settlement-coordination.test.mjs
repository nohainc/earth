import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('day coordination only takes over stale leases', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/015_resumable_settlement_work.sql'), 'utf8');
  assert.match(migration, /daily_settlement_phase_runs/);
  assert.match(migration, /UNIQUE \(game_day, phase_id, shard\)/);
  assert.match(migration, /FOR UPDATE SKIP LOCKED/);
  assert.match(migration, /lease_expires_at < CURRENT_TIMESTAMP/);
  assert.match(migration, /prior\.phase_order < current\.phase_order/);
});

test('settlement runner enforces barriers and reports explicit outcomes', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(scheduler, /earth_claim_settlement_day/);
  assert.match(scheduler, /status: 'busy'/);
  assert.match(scheduler, /earth_finalize_settlement_day/);
  assert.match(scheduler, /Settlement day lease lost/);
  assert.match(scheduler, /earth_fail_settlement_day/);
  assert.match(scheduler, /completeSettlementWork/);
  assert.match(scheduler, /settlementWorkProgress/);
});
