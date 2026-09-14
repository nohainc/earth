import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const construction = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
const settlement = fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8');
const migration = fs.readFileSync('db/migrations/014_construction_settlement_destination.sql', 'utf8');

test('construction CREDIT uses explicit settlement classification and destination', () => {
  assert.match(construction, /ECON-CONSTRUCTION-SETTLEMENT/);
  assert.match(construction, /PRIVATE_CONSTRUCTION/);
  assert.match(construction, /PUBLIC_INFRASTRUCTURE_CONSTRUCTION/);
  assert.match(construction, /construction-credit-v1/);
  assert.doesNotMatch(construction, /o\.id\s*=\s*'EARTH'/);
  assert.doesNotMatch(construction, /earthTreasury/);
});

test('private construction uses House resources while public construction has no resource inputs', () => {
  assert.match(construction, /if \(isPublic\) return \[\];/);
  assert.match(construction, /loadConstructionRequirements\(tx, catalog\.id, ownerEconomicId, isPublic\)/);
  assert.match(construction, /ownerEconomicId, isPublic \? 'TREASURY' : 'WALLET'/);
});

test('private operating CREDIT uses explicit non-EARTH settlement routing', () => {
  assert.match(settlement, /ECON-CONSTRUCTION-SETTLEMENT/);
  assert.match(settlement, /PRIVATE_BUILDING_OPERATION/);
  assert.doesNotMatch(settlement, /ECON-EARTH-001/);
  assert.doesNotMatch(settlement, /'SETTLEMENT'/);
});

test('construction settlement account is provisioned as a SYSTEM CREDIT account', () => {
  assert.match(migration, /ECON-CONSTRUCTION-SETTLEMENT/);
  assert.match(migration, /'SYSTEM_ACCOUNT'/);
  assert.match(migration, /WHERE code = 'CREDIT'/);
});
