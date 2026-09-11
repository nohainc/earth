import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('succession is House-level and never nominates another active Human', () => {
  const migration = read('db/migrations/297_house_succession_plans.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /CREATE TABLE IF NOT EXISTS house_succession_plans/);
  assert.match(migration, /house_id TEXT PRIMARY KEY REFERENCES houses/);
  assert.doesNotMatch(migration, /successor_human_id/);
  assert.match(schema, /house_succession_plans/);
  assert.match(lifecycle, /house_succession_plans/);
  assert.match(lifecycle, /processHouseMortality/);
  assert.match(lifecycle, /Emergency Successor of/);
  assert.match(lifecycle, /owner_economic_id/);
});
