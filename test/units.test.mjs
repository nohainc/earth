import test from 'node:test';
import assert from 'node:assert/strict';
import { formatFixedUnits, nonNegativeBigInt, parseFixedUnits, roundDivide } from '../cloudflare/src/units.ts';

test('fixed-point primitives preserve values beyond JavaScript safe integers', () => {
  const value = parseFixedUnits('9007199254740991.999999', 1_000_000n, 6);
  assert.equal(value, 9007199254740991999999n);
  assert.equal(formatFixedUnits(value, 1_000_000n, 6), '9007199254740991.999999');
});

test('fixed-point division has explicit symmetric half-up rounding', () => {
  assert.equal(roundDivide(5n, 2n), 3n);
  assert.equal(roundDivide(-5n, 2n), -3n);
  assert.equal(roundDivide(4n, 2n), 2n);
});

test('authoritative unit parser rejects malformed and negative values', () => {
  assert.throws(() => parseFixedUnits('1.0000001', 1_000_000n, 6), /Invalid fixed-point/);
  assert.throws(() => nonNegativeBigInt('-1', 'balance'), /balance must be non-negative/);
  assert.equal(nonNegativeBigInt('9007199254740991999999'), 9007199254740991999999n);
});
