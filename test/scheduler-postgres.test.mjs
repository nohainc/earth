import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('scheduler heartbeat is decoupled from world-clock mutation', () => {
  const scheduler = fs.readFileSync('cloudflare/src/scheduler.ts', 'utf8');
  const postgresScheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  assert.match(scheduler, /runSchedulerHeartbeat/);
  assert.match(postgresScheduler, /readAuthoritativeGameTime/);
  assert.doesNotMatch(scheduler, /minutesPerTick/);
  assert.doesNotMatch(postgresScheduler, /minutesPerTick|validateWorldAdvanceMinutes|advance_world_clock/);
});
