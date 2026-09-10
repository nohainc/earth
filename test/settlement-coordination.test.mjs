import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('day coordination only takes over stale leases', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/182_scheduler_day_coordination.sql'), 'utf8');
  assert.match(migration, /ON CONFLICT \(game_day\) DO NOTHING/);
  assert.match(migration, /current_run\.lease_owner <> p_lease_owner/);
  assert.match(migration, /status := 'busy'/);
  assert.match(migration, /COALESCE\(current_run\.lease_heartbeat_at, current_run\.started_at\) > stale_before/);
});

test('settlement runner enforces barriers and reports explicit outcomes', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(scheduler, /earth_claim_settlement_day/);
  assert.match(scheduler, /status: 'partial'/);
  assert.match(scheduler, /status: 'busy'/);
  assert.match(scheduler, /earth_complete_settlement_day/);
  assert.match(scheduler, /Settlement day completion lease lost/);
  assert.match(scheduler, /earth_fail_settlement_day/);
  assert.match(scheduler, /setInterval\(\(\) => \{[\s\S]*earth_heartbeat_settlement_day/);
  assert.match(scheduler, /earth_heartbeat_settlement_phase/);
});
