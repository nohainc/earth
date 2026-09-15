import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyBuildingEconomicRole } from '../cloudflare/src/building-economy-role.ts';
import fs from 'node:fs';

test('building economic roles classify canonical catalog facts deterministically', () => {
  assert.equal(classifyBuildingEconomicRole({ ownershipScope: 'PUBLIC', outputUnits: { ENERGY: 1 } }), 'INFRASTRUCTURE');
  assert.equal(classifyBuildingEconomicRole({ ownershipScope: 'PRIVATE', serviceType: 'HEALTH', serviceCapacityUnits: '10' }), 'SERVICE');
  assert.equal(classifyBuildingEconomicRole({ ownershipScope: 'PRIVATE', inputUnits: { MATERIAL: '2' }, outputUnits: { COMPONENTS: '1' } }), 'TRANSFORMER');
  assert.equal(classifyBuildingEconomicRole({ ownershipScope: 'PRIVATE', outputUnits: { FOOD: '80' } }), 'PRODUCER');
  assert.equal(classifyBuildingEconomicRole({ ownershipScope: 'PRIVATE', inputUnits: {}, outputUnits: {} }), 'ESTATE');
});

test('V4-115 separates commercial service providers from public infrastructure', () => {
  const routes = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
  const settlement = fs.readFileSync('cloudflare/src/service-settlement-postgres.ts', 'utf8');
  const migration = fs.readFileSync('db/migrations/054_building_economic_roles.sql', 'utf8');
  assert.match(migration, /economic_role/);
  assert.match(routes, /c\.economic_role/);
  assert.match(settlement, /c\.economic_role = 'SERVICE'/);
});
