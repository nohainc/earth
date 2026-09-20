import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { compileHousePolicy } from '../cloudflare/src/house-policy-execution.ts';

const resources = ['FOOD', 'ENERGY', 'MATERIAL', 'COMPONENTS', 'COMPUTE'];

function policy(overrides = {}) {
  return {
    id: 'AUTOMATION-1', houseId: 'HOUSE-1', policyType: 'OPERATING', version: 1,
    effectiveFromGameDay: 1, status: 'ACTIVE', operatingMode: 'BALANCED',
    dailySpendCapUnits: 10_000n, minimumReserveUnits: {}, sellAboveUnits: {},
    maxInputPriceUnits: {}, minSalePriceUnits: {}, maxBuyQuantityUnits: {},
    maxSellQuantityUnits: {}, rulesVersion: 'automation-v1', ...overrides,
  };
}

test('all five resources use exact inventory and price scales', () => {
  const result = compileHousePolicy(policy({
    dailySpendCapUnits: 1_000_000_000n,
    minimumReserveUnits: Object.fromEntries(resources.map((resource) => [resource, 100_000_000n])),
    maxInputPriceUnits: Object.fromEntries(resources.map((resource) => [resource, 250n])),
    maxBuyQuantityUnits: Object.fromEntries(resources.map((resource) => [resource, 100_000_000n])),
  }), {
    FOOD: 25_000_000n, ENERGY: 0n, MATERIAL: 100_000_000n,
    COMPONENTS: 10_000_000n, COMPUTE: 80_000_000n,
  }, 0n);

  assert.deepEqual(result.actions.map((action) => [action.product, action.quantityUnits]), [
    ['FOOD', 75_000_000n], ['ENERGY', 100_000_000n],
    ['COMPONENTS', 90_000_000n], ['COMPUTE', 20_000_000n],
  ]);
  assert.equal(result.actions.every((action) => action.limitPriceUnits === 250n), true);
});

test('spend cap bounds multiple partial shortfall buys without exceeding the cap', () => {
  const result = compileHousePolicy(policy({
    dailySpendCapUnits: 10_000n,
    minimumReserveUnits: { FOOD: 100_000_000n, ENERGY: 100_000_000n },
    maxInputPriceUnits: { FOOD: 250n, ENERGY: 250n },
    maxBuyQuantityUnits: { FOOD: 100_000_000n, ENERGY: 100_000_000n },
  }), { FOOD: 25_000_000n, ENERGY: 0n }, 0n);
  const reserved = result.actions.reduce((total, action) => total + (action.quantityUnits * action.limitPriceUnits + 500_000n) / 1_000_000n, 0n);
  assert.equal(reserved <= 10_000n, true);
  assert.equal(result.actions[0].quantityUnits, 40_000_000n);
  assert.equal(result.exceptions[0].reasonCode, 'SPEND_CAP_EXHAUSTED');
});

test('reserve and sell-above bands do not oscillate at the thresholds', () => {
  const configured = policy({
    minimumReserveUnits: { FOOD: 10_000_000n }, sellAboveUnits: { FOOD: 15_000_000n },
    maxInputPriceUnits: { FOOD: 100n }, minSalePriceUnits: { FOOD: 100n },
  });
  assert.deepEqual(compileHousePolicy(configured, { FOOD: 12_000_000n }, 0n).actions, []);
  assert.equal(compileHousePolicy(configured, { FOOD: 20_000_000n }, 0n).actions[0].quantityUnits, 5_000_000n);
  assert.deepEqual(compileHousePolicy(configured, { FOOD: 15_000_000n }, 0n).actions, []);
});

test('sale quantity limits are enforced independently of the sell-above threshold', () => {
  const result = compileHousePolicy(policy({
    sellAboveUnits: { MATERIAL: 10_000_000n }, minSalePriceUnits: { MATERIAL: 300n },
    maxSellQuantityUnits: { MATERIAL: 2_000_000n },
  }), { MATERIAL: 25_000_000n }, 0n);
  assert.equal(result.actions[0].actionType, 'SELL');
  assert.equal(result.actions[0].quantityUnits, 2_000_000n);
});

test('settlement integration uses scheduled activation, disabled filtering, open-order skips, retries, and Spot escrow', () => {
  const execution = fs.readFileSync('cloudflare/src/house-policy-execution.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  const migration = fs.readFileSync('db/migrations/150_house_automation_execution_audit.sql', 'utf8');

  assert.match(execution, /effective_from_game_day <= \$1/);
  assert.match(execution, /enabled = TRUE/);
  assert.match(execution, /o\.status IN \('OPEN', 'PARTIAL'\)/);
  assert.match(execution, /OPEN_ORDER_EXISTS/);
  assert.match(execution, /SELECT 1 FROM policy_execution_log WHERE action_correlation_id = \$1/);
  assert.match(execution, /ON CONFLICT \(action_correlation_id\) DO NOTHING/);
  assert.match(execution, /submitMarketOrder\(repository/);
  assert.match(execution, /sourceType: 'HOUSE_POLICY'/);
  assert.match(execution, /goodTilGameDay: gameDay \+ 1/);
  assert.match(scheduler, /housePolicyExecution/);
  assert.match(migration, /policy_execution_daily_summaries/);
  assert.match(migration, /CHECK \(execution_status IN/);
});
