import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const engine = fs.readFileSync(new URL('../cloudflare/src/building-settlement-v2.ts', import.meta.url), 'utf8');
const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');

test('building settlement has separate private and public clean-schema paths', () => {
  assert.match(engine, /BuildingSettlementResult/);
  assert.match(engine, /settlePrivateBuilding/);
  assert.match(engine, /settlePublicBuilding/);
  assert.match(engine, /RESOURCE_CONSUMPTION/);
  assert.match(engine, /RESOURCE_PRODUCTION/);
  assert.match(engine, /CORPORATION_PUBLIC_SPENDING/);
  assert.match(engine, /earth_refresh_territory_capacity/);
  for (const legacy of ['city_id', 'ownership_class', 'building_settlement_journals', 'settlement_effects', 'account_type = [0-9]', 'balance::']) {
    assert.doesNotMatch(engine, new RegExp(legacy));
  }
});

test('daily building phase uses the V2 effects boundary', () => {
  assert.match(scheduler, /settleBuildingUpkeepAndRevenueV2\(tx, day\)/);
});
