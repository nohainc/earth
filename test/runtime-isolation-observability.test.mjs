import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('repository supports distinct API and scheduler timeout profiles', () => {
  const repository = fs.readFileSync(path.resolve('cloudflare/src/repository.ts'), 'utf8');
  const index = fs.readFileSync(path.resolve('cloudflare/src/index.ts'), 'utf8');
  assert.match(repository, /RepositoryWorkload = 'api' \| 'scheduler'/);
  assert.match(repository, /EARTH_API_STATEMENT_TIMEOUT_MS/);
  assert.match(repository, /EARTH_SCHEDULER_STATEMENT_TIMEOUT_MS/);
  assert.match(repository, /EARTH_SCHEDULER_LOCK_TIMEOUT_MS/);
  assert.match(index, /workload: 'scheduler'/);
});

test('scheduler records durable run telemetry and isolates outbox delivery', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler.ts'), 'utf8');
  const index = fs.readFileSync(path.resolve('cloudflare/src/index.ts'), 'utf8');
  const health = fs.readFileSync(path.resolve('cloudflare/src/health.ts'), 'utf8');
  assert.match(scheduler, /INSERT INTO scheduler_runs/);
  assert.match(scheduler, /settlement_watermark_before/);
  assert.match(scheduler, /backlog_after/);
  assert.match(index, /Scheduler outbox delivery failed after committed economy work/);
  assert.match(index, /outbox_events_delivered/);
  assert.match(health, /schedulerState/);
  assert.match(health, /180/);
  assert.match(health, /600/);
});
