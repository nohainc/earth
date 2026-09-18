import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/132_settlement_finalization_barrier.sql', 'utf8');
const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');

test('settlement finalization requires reconciliation before cursor advancement', () => {
  assert.match(migration, /earth_finalize_settlement_day/);
  assert.match(migration, /v_shadow_status NOT IN \('reconciled', 'skipped'\)/);
  assert.match(migration, /status = 'completed'/);
  assert.match(migration, /earth_advance_settlement_cursor\(p_game_day\)/);
  assert.ok(migration.indexOf("status = 'completed'") < migration.indexOf('earth_advance_settlement_cursor'));
});

test('reconciliation failure leaves settlement failed and prevents finalization', () => {
  const reconcile = scheduler.indexOf('await reconcileEconomyShadowDay(repository, gameDay)');
  const finalize = scheduler.indexOf("earth_finalize_settlement_day($1)");
  const failure = scheduler.indexOf("SET status = 'failed'");
  assert.ok(reconcile >= 0 && finalize > reconcile && failure > reconcile);
  assert.match(scheduler, /return \{ status: 'failed', gameDay/);
  assert.doesNotMatch(scheduler.slice(0, reconcile), /earth_finalize_settlement_day/);
});
