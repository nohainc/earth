import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateInventoryPolicy, evaluateSalePolicy } from '../cloudflare/src/house-policy.ts';

const policy = {
  id: 'POLICY-1', houseId: 'HOUSE-1', policyType: 'MARKET_STANDING', version: 1,
  effectiveFromGameDay: 10, status: 'ACTIVE', operatingMode: 'BALANCED',
  dailySpendCapUnits: 100n, reserveFloorUnits: { ENERGY: 20n },
  maxInputPriceUnits: { ENERGY: 4n }, minSalePriceUnits: { FOOD: 8n },
  procurementQuantityUnits: { ENERGY: 10n }, rulesVersion: 'policies-v1',
};

test('inventory policy produces deterministic bounded procurement decisions', () => {
  assert.deepEqual(evaluateInventoryPolicy(policy, { ENERGY: 5n }, 0n), [{ action: 'BUY', product: 'ENERGY', quantityUnits: 10n, priceLimitUnits: 4n, reason: 'ENERGY is below the saved House reserve floor' }]);
  assert.deepEqual(evaluateInventoryPolicy({ ...policy, status: 'PAUSED' }, { ENERGY: 0n }, 0n), []);
  assert.throws(() => evaluateInventoryPolicy(policy, { ENERGY: 1n }, 101n), /outside the configured cap/);
});

test('sale policy never sells through the saved reserve floor', () => {
  assert.deepEqual(evaluateSalePolicy(policy, { FOOD: 30n }), [{ action: 'SELL', product: 'FOOD', quantityUnits: 30n, priceLimitUnits: 8n, reason: 'FOOD is above the saved House reserve floor' }]);
  assert.deepEqual(evaluateSalePolicy(policy, { ENERGY: 20n }), []);
});
