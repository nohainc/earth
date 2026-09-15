import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('world conditions are created only by validated, executed governance actions', () => {
  const migration = fs.readFileSync('db/migrations/056_governed_world_conditions.sql', 'utf8');
  const governance = fs.readFileSync('cloudflare/src/governance-v4-postgres.ts', 'utf8');
  assert.match(migration, /WORLD_CONDITION/);
  assert.match(governance, /WORLD_CONDITION/);
  assert.match(governance, /executeWorldCondition/);
  assert.match(governance, /governance_executions_v4/);
  assert.match(governance, /effectiveFrom < day \+ 1/);
  assert.match(governance, /modifierBps/);
});
