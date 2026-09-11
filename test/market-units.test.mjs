import test from 'node:test';
import assert from 'node:assert/strict';
import {
  calculateFeeUnits,
  calculateQuoteUnits,
  displayPriceToUnits,
  displayQuantityToUnits,
  priceUnitsToDisplayPrice,
  unitsToDisplayQuantity,
} from '../cloudflare/src/market-units.ts';

test('market display values convert to exact atomic units', () => {
  assert.equal(displayQuantityToUnits(10.5), 10_500_000n);
  assert.equal(displayPriceToUnits('29.50'), 2_950n);
  assert.equal(unitsToDisplayQuantity(10_500_000n), '10.500000');
  assert.equal(priceUnitsToDisplayPrice(2_950n), '29.50');
});

test('market quote and fee calculations are integer-only and deterministic', () => {
  const quote = calculateQuoteUnits(10_500_000n, 2_950n);
  assert.equal(quote, 30_975n);
  assert.equal(calculateFeeUnits(quote, '0.05'), 1_549n);
});
