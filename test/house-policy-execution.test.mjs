import test from 'node:test';
import assert from 'node:assert/strict';
import { compileHousePolicy } from '../cloudflare/src/house-policy-execution.ts';

const policy = {
  id: 'p', houseId: 'h', policyType: 'INVENTORY_RESERVE', version: 1,
  effectiveFromGameDay: 1, status: 'ACTIVE', operatingMode: 'BALANCED',
  dailySpendCapUnits: 100n, reserveFloorUnits: { FOOD: 10n },
  maxInputPriceUnits: { FOOD: 7n }, minSalePriceUnits: {},
  procurementQuantityUnits: { FOOD: 30n }, rulesVersion: 'v1',
};

test('policy compiler bounds ordinary market actions by remaining spend', () => {
  const result = compileHousePolicy(policy, { FOOD: 0n }, 30n);
  assert.equal(result.exceptions.length, 0);
  assert.equal(result.actions[0].product, 'FOOD');
  assert.equal(result.actions[0].quantityUnits, 10n);
  assert.equal(result.actions[0].source, 'HOUSE_POLICY');
});

test('policy compiler emits an exception when an order cannot be safely priced', () => {
  const unpriced = { ...policy, maxInputPriceUnits: {} };
  const result = compileHousePolicy(unpriced, { FOOD: 0n }, 0n);
  assert.equal(result.actions.length, 0);
  assert.match(result.exceptions[0].reason, /maximum input price/);
});
