import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('scheduler heartbeat owns catch-up limits and safe processing watermark', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler.ts'), 'utf8');
  assert.match(scheduler, /export async function runSchedulerHeartbeat/);
  const index = fs.readFileSync(path.resolve('cloudflare/src/index.ts'), 'utf8');
  assert.match(index, /EARTH_SCHEDULER_MAX_CATCHUP_DAYS/);
  assert.match(index, /EARTH_SCHEDULER_WORK_BUDGET_MS/);
  assert.match(scheduler, /settlementWatermark/);
  assert.match(scheduler, /position\.watermark < position\.day - 1/);
  assert.match(scheduler, /nextDay = position\.watermark \+ 1/);
  assert.match(scheduler, /safeProcessedGameDay/);
});

test('health uses contiguous settlement watermark rather than maximum completed day', () => {
  const health = fs.readFileSync(path.resolve('cloudflare/src/health.ts'), 'utf8');
  assert.match(health, /earth_settlement_watermark/);
  assert.doesNotMatch(health, /ORDER BY game_day DESC LIMIT 1/);
});
