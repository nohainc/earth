import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/329_city_service_capacity_projection.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');
const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');

test('city service capacity is a daily Building V2 projection consumed by city dynamics', () => {
  for (const field of ['housing_capacity', 'energy_capacity', 'connectivity_capacity', 'health_capacity', 'service_demand', 'coverage_ratio']) {
    assert.match(migration, new RegExp(field));
    assert.match(schema, new RegExp(field));
  }
  assert.match(migration, /building_settlement_journals/);
  assert.match(migration, /building_catalog/);
  assert.match(migration, /earth_refresh_city_service_capacity_daily/);
  assert.match(scheduler, /earth_refresh_city_service_capacity_daily/);
  assert.match(scheduler, /city_service_capacity_daily/);
  assert.doesNotMatch(migration, /UPDATE cities\s+SET\s+(housing_capacity|energy_capacity|connectivity_capacity|health_capacity)/i);
});
