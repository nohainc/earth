import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const engine = fs.readFileSync(new URL('../cloudflare/src/building-settlement-v2.ts', import.meta.url), 'utf8');
const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');

test('V2 building settlement calculates results and emits effects without balance mutation', () => {
  assert.match(engine, /BuildingSettlementResult/);
  assert.match(engine, /canOperate/);
  assert.match(engine, /requestedUpkeep/);
  assert.match(engine, /paidUpkeep/);
  assert.match(engine, /productionOutput/);
  assert.match(engine, /serviceCapacity/);
  assert.match(engine, /customerDemand/);
  assert.match(engine, /actualSales/);
  assert.match(engine, /actualRevenue/);
  assert.match(engine, /conditionDelta/);
  assert.match(engine, /repairCost/);
  assert.match(engine, /INSERT INTO settlement_effects/);
  assert.doesNotMatch(engine, /UPDATE economic_accounts/);
  assert.doesNotMatch(engine, /UPDATE account_balances/);
  assert.doesNotMatch(engine, /UPDATE resource_balances/);
});

test('daily building phase uses the V2 effects boundary', () => {
  assert.match(scheduler, /settleBuildingUpkeepAndRevenueV2\(tx, settlementDay\)/);
});
