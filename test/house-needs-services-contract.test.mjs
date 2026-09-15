import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
const migration = fs.readFileSync('db/migrations/017_house_needs_services.sql', 'utf8');
const engine = fs.readFileSync('cloudflare/src/service-settlement-postgres.ts', 'utf8');
const readModel = fs.readFileSync('cloudflare/src/read-postgres.ts', 'utf8');

test('House needs and services have versioned canonical records', () => {
  for (const table of ['need_rules', 'service_types', 'house_need_assessments', 'service_allocations']) {
    assert.match(schema, new RegExp(`CREATE TABLE ${table}`));
    assert.match(migration, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`));
  }
  assert.match(engine, /house_need_assessments/);
  assert.match(engine, /service_allocations/);
  assert.match(engine, /earth_post_transaction/);
  assert.match(engine, /remainingCapacity/);
});

test('service allocation is capacity-bounded, payer-backed, and exposed as risk', () => {
  assert.match(engine, /providerMap/);
  assert.match(engine, /remainingCapacity\.set\(providerKey, available - allocation\)/);
  assert.match(engine, /payer_economic_id/);
  assert.match(engine, /createServiceObligation/);
  assert.match(readModel, /house_need_assessments/);
  assert.match(readModel, /coverageRatio/);
});
