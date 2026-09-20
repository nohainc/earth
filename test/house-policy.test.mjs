import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateInventoryPolicy, evaluateSalePolicy, validateHousePolicy } from '../cloudflare/src/house-policy.ts';

const policy = {
  id: 'POLICY-1', houseId: 'HOUSE-1', policyType: 'MARKET_STANDING', version: 1,
  effectiveFromGameDay: 10, status: 'ACTIVE', operatingMode: 'BALANCED',
  dailySpendCapUnits: 100n, minimumReserveUnits: { ENERGY: 20n }, sellAboveUnits: { FOOD: 20n },
  maxInputPriceUnits: { ENERGY: 4n }, minSalePriceUnits: { FOOD: 8n },
  maxBuyQuantityUnits: { ENERGY: 10n }, maxSellQuantityUnits: {}, rulesVersion: 'policies-v1',
};

test('inventory policy produces deterministic bounded procurement decisions', () => {
  assert.deepEqual(evaluateInventoryPolicy(policy, { ENERGY: 5n }, 0n), [{ action: 'BUY', product: 'ENERGY', quantityUnits: 10n, priceLimitUnits: 4n, reasonCode: 'MINIMUM_RESERVE_SHORTFALL', reason: 'ENERGY is below the saved minimum reserve' }]);
  assert.deepEqual(evaluateInventoryPolicy({ ...policy, status: 'PAUSED' }, { ENERGY: 0n }, 0n), []);
  assert.throws(() => evaluateInventoryPolicy(policy, { ENERGY: 1n }, 101n), /outside the configured cap/);
});

test('an explicit zero procurement quantity disables buying for that resource', () => {
  const result = evaluateInventoryPolicy(
    { ...policy, maxBuyQuantityUnits: { ENERGY: 0n } },
    { ENERGY: 0n },
    0n,
  );
  assert.deepEqual(result, []);
});

test('sale policy never sells through the saved reserve floor', () => {
  assert.deepEqual(evaluateSalePolicy(policy, { FOOD: 30n }), [{ action: 'SELL', product: 'FOOD', quantityUnits: 10n, priceLimitUnits: 8n, reasonCode: 'SELL_ABOVE_THRESHOLD', reason: 'FOOD is above the saved sell-above threshold' }]);
  assert.deepEqual(evaluateSalePolicy(policy, { ENERGY: 20n }), []);
});

test('buy quantity is capped by the configured maximum, not substituted for the shortfall', () => {
  assert.equal(evaluateInventoryPolicy(policy, { ENERGY: 0n }, 0n)[0].quantityUnits, 10n);
  assert.equal(evaluateInventoryPolicy({ ...policy, maxBuyQuantityUnits: { ENERGY: 100n } }, { ENERGY: 15n }, 0n)[0].quantityUnits, 5n);
});

test('resource policy validation rejects unknown resources, non-positive prices, and inverted thresholds', () => {
  assert.throws(() => validateHousePolicy({ ...policy, minimumReserveUnits: { WATER: 1n } }), /unknown resource code/);
  assert.throws(() => validateHousePolicy({ ...policy, maxInputPriceUnits: { ENERGY: 0n } }), /outside the supported integer bounds/);
  assert.throws(() => validateHousePolicy({ ...policy, minimumReserveUnits: { FOOD: 10n }, sellAboveUnits: { FOOD: 1n } }), /below minimumReserve/);
});
