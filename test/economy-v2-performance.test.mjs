import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('Economy V2 performance benchmark covers population, pipeline, concurrency, and partition measurements', () => {
  const source = fs.readFileSync(path.resolve('scripts/benchmark-economy-v2.mjs'), 'utf8');
  for (const scale of ['100', '1000', '10000', '100000', '1000000']) assert.match(source, new RegExp(scale));
  for (const metric of ['profile_rebuild', 'effect_generation', 'netting', 'posting', 'entryVolume', 'memoryBytes', 'lockWaitMs', 'deadlocks', 'QUERY PLAN', 'BUFFERS']) assert.match(source, new RegExp(metric));
  assert.match(source, /ROLLBACK/);
  assert.match(source, /ORDER BY account_id/);
});
