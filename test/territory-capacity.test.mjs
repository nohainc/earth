import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('Territory capacity is an authoritative rebuildable projection', () => {
  const schema = read('db/baseline/01_schema.sql');
  const functions = read('db/baseline/02_functions.sql');
  assert.match(schema, /CREATE TABLE territory_capacity_state/);
  assert.match(schema, /ownership_scope TEXT NOT NULL DEFAULT 'PRIVATE'/);
  for (const column of ['house_capacity', 'population_capacity', 'private_slot_capacity', 'public_slot_capacity', 'housing_capacity', 'health_capacity', 'energy_capacity', 'connectivity_capacity']) {
    assert.match(schema, new RegExp(`\\b${column}\\b`), column);
  }
  assert.match(functions, /CREATE OR REPLACE FUNCTION earth_refresh_territory_capacity/);
  assert.match(functions, /INSERT INTO territory_capacity_state/);
  assert.match(functions, /FROM house_affiliations ha/);
  assert.match(functions, /FROM buildings b/);
});

test('Building scarcity is addressed through Territory, never City governance', () => {
  const capacity = read('cloudflare/src/territory-capacity-postgres.ts');
  const routes = read('cloudflare/src/real-estate-routes.ts');
  assert.match(capacity, /getTerritoryCapacity/);
  assert.match(capacity, /territory_capacity_state/);
  assert.match(capacity, /private_slot_capacity/);
  assert.match(capacity, /public_slot_capacity/);
  assert.match(capacity, /owner_type = 'CORPORATION'/);
  assert.match(capacity, /ownership_scope/);
  assert.match(capacity, /ownerType/);
  assert.match(capacity, /territory_id/);
  assert.match(routes, /territoryId/);
  assert.match(routes, /territoryCapacityMatch/);
  for (const source of [capacity, routes]) assert.doesNotMatch(source, /cities|city_id|cityId|CITY/);
});

test('Corporation is the sole local fiscal authority', () => {
  const schema = read('db/baseline/01_schema.sql');
  const fiscal = read('cloudflare/src/corporation-fiscal-postgres.ts');
  const reference = read('db/baseline/03_reference_data.sql');
  assert.match(schema, /institution_kind TEXT NOT NULL CHECK \(institution_kind = 'CORPORATION'\)/);
  assert.match(schema, /scope TEXT NOT NULL CHECK \(scope IN \('EARTH','CORPORATION'\)\)/);
  assert.match(reference, /'EARTH'/);
  assert.match(reference, /'CORPORATION'/);
  assert.match(fiscal, /spendCorporationBudget/);
  assert.match(fiscal, /CORPORATION_PUBLIC_SPENDING/);
  assert.match(fiscal, /institution_budget_lines/);
  assert.doesNotMatch(fiscal, /cities|city_id|OUC|CITY/);
});

test('Governance has two arenas and supports Territory targets', () => {
  const schema = read('db/baseline/01_schema.sql');
  const governance = read('cloudflare/src/governance-v3-postgres.ts');
  const routes = read('cloudflare/src/governance-routes.ts');
  assert.match(schema, /target_type TEXT NOT NULL DEFAULT 'INSTITUTION'/);
  assert.match(schema, /target_type IN \('INSTITUTION','TERRITORY'\)/);
  assert.match(governance, /kind IN \('EARTH', 'CORPORATION'\)/);
  assert.match(governance, /territoryId/);
  assert.match(governance, /Corporation may only target its own Territory/);
  assert.match(routes, /'territory'/);
  assert.doesNotMatch(governance, /cities|city_id|CITY|OUC/);
});
