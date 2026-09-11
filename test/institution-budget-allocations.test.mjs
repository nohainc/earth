import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('corporation city-support allocations separate authority from funded cash', () => {
  const migration = read('db/migrations/324_institution_budget_allocations.sql');
  const schema = read('db/schema.sql');
  assert.match(migration, /CREATE TABLE institution_budget_allocations/);
  assert.match(migration, /parent_institution_id/);
  assert.match(migration, /child_institution_id/);
  assert.match(migration, /funded_units BIGINT NOT NULL DEFAULT 0/);
  assert.match(migration, /funded_units <= authorized_units/);
  assert.match(migration, /CITY_SUPPORT/);
  assert.match(migration, /earth_set_budget_allocation/);
  assert.match(migration, /Child allocations exceed the corporation CITY_SUPPORT envelope/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS institution_budget_allocations/);
});
