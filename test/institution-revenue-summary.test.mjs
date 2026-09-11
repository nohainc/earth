import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('institution revenue is a projection and does not mutate budget authority', () => {
  const migration = read('db/migrations/327_institution_revenue_summary.sql');
  const schema = read('db/schema.sql');
  assert.match(migration, /CREATE TABLE institution_revenue_summary/);
  for (const field of ['taxes_received', 'service_revenue', 'grants_received', 'license_income', 'other_income']) assert.match(migration, new RegExp(field));
  assert.match(migration, /earth_refresh_institution_revenue_summary/);
  assert.match(migration, /e.delta > 0/);
  assert.doesNotMatch(migration, /UPDATE institution_budget_lines/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS institution_revenue_summary/);
});
