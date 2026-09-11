import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('House cutover retires cross-Human succession entry points', () => {
  const migration = read('db/migrations/314_house_cutover_cleanup.sql');
  const schema = read('db/schema.sql');
  const index = read('cloudflare/src/index.ts');
  const authRoutes = read('cloudflare/src/auth-routes.ts');
  const lifecycleEngine = read('cloudflare/src/engines/lifecycle-engine.ts');

  assert.match(migration, /DROP COLUMN IF EXISTS successor_human_id/);
  assert.match(migration, /DROP COLUMN IF EXISTS estate_period_days/);
  assert.doesNotMatch(schema, /successor_human_id TEXT REFERENCES humans\(id\)\n\);/);
  assert.match(index, /Cross-Human successors are no longer supported/);
  assert.match(authRoutes, /Cross-Human inheritance is retired/);
  assert.match(lifecycleEngine, /processHouseMortality/);
  assert.doesNotMatch(lifecycleEngine, /processMortality/);
});
