import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('scheduler heartbeat configures catch-up limits and delegates to single tick orchestrator', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler.ts'), 'utf8');
  assert.match(scheduler, /export async function runSchedulerHeartbeat/);
  const index = fs.readFileSync(path.resolve('cloudflare/src/index.ts'), 'utf8');
  assert.match(index, /EARTH_SCHEDULER_MAX_CATCHUP_DAYS/);
  assert.match(index, /EARTH_SCHEDULER_WORK_BUDGET_MS/);
  assert.match(scheduler, /settlementWatermark/);
  assert.match(scheduler, /safeProcessedGameDay/);

  // Single orchestrator: scheduler.ts delegates to runWorldSchedulerTick with options
  // and does NOT contain an outer catch-up while loop.
  assert.match(scheduler, /runWorldSchedulerTick\(/);
  assert.match(scheduler, /\{\s*maxCatchupDays,\s*workBudgetMs\s*\}/);
  assert.doesNotMatch(scheduler, /while\s*\(/);

  // Single orchestrator: scheduler-postgres.ts owns the sequential catch-up loop
  const schedulerPg = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(schedulerPg, /while\s*\(currentSettled < targetDay && settledDays < maxCatchupDays && Date\.now\(\) - startedAt < workBudgetMs\)/);
});

test('health uses contiguous settlement watermark rather than maximum completed day', () => {
  const health = fs.readFileSync(path.resolve('cloudflare/src/health.ts'), 'utf8');
  assert.match(health, /settled_through_game_day/);
  assert.doesNotMatch(health, /ORDER BY game_day DESC LIMIT 1\)\s*completed/);
});


