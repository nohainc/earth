import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('physical resource behavior metadata distinguishes staged stock and flow semantics', () => {
  const migration = fs.readFileSync('db/migrations/020_resource_behavior_metadata.sql', 'utf8');
  const repository = fs.readFileSync('cloudflare/src/resource-behavior-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/economic-routes.ts', 'utf8');
  assert.match(migration, /PERISHABLE_STOCK/);
  assert.match(migration, /CAPACITY_ENTITLEMENT/);
  assert.match(migration, /decay_bps_per_day/);
  assert.match(repository, /stagedSemantics/);
  assert.match(routes, /resources\/metadata/);
});
