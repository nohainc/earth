import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('required settlement phases are not silently wired to no-op handlers', () => {
  const source = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  const registry = fs.readFileSync('cloudflare/src/daily-settlement-phases.ts', 'utf8');
  const requiredNoOps = [...registry.matchAll(/required\('([^']+)'[^\n]+handlers\.(\w+)\)/g)].filter((match) => new RegExp(`${match[2]}:\\s*noOpPhase`).test(source));
  assert.deepEqual(requiredNoOps, []);
  assert.match(registry, /deferred\('profile_rebuild'/);
  assert.match(source, /activatePendingHouseSuccessors/);
});
