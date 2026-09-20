import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('world conditions are not created by the retired V4 governance authority', () => {
  const migration = fs.readFileSync('db/migrations/173_retire_v4_world_condition_authority.sql', 'utf8');
  const governance = fs.readFileSync('cloudflare/src/governance-v4-postgres.ts', 'utf8');
  const outcomes = fs.readFileSync('cloudflare/src/initiative-outcomes.ts', 'utf8');
  assert.doesNotMatch(migration, /'WORLD_CONDITION'/);
  assert.doesNotMatch(governance, /WORLD_CONDITION/);
  assert.doesNotMatch(governance, /world_conditions/);
  assert.match(outcomes, /world_conditions/);
  assert.match(outcomes, /'EARTH'/);
});
