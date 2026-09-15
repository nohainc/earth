import test from 'node:test';
import assert from 'node:assert/strict';
import { calculatePerishableDecayUnits } from '../cloudflare/src/resource-settlement-postgres.ts';

test('perishable decay uses bounded integer units and never exceeds stock', () => {
  assert.equal(calculatePerishableDecayUnits(1000n, 500), 50n);
  assert.equal(calculatePerishableDecayUnits(1n, 500), 0n);
  assert.throws(() => calculatePerishableDecayUnits(-1n, 500), /negative/);
  assert.throws(() => calculatePerishableDecayUnits(1n, 10001), /bounds/);
});
