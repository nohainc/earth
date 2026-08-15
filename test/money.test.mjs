import test from 'node:test';
import assert from 'node:assert/strict';
import { centsToMoney, moneyToCents, rateToMicros, taxToCents } from '../cloudflare/src/money.ts';

test('parses and formats money without floating-point drift', () => {
  assert.equal(moneyToCents('0.10'), 10n);
  assert.equal(moneyToCents('123.45'), 12345n);
  assert.equal(centsToMoney(1000000000000000001n), '10000000000000000.01');
});

test('calculates tax with exact six-decimal rate arithmetic', () => {
  assert.equal(rateToMicros('0.125000'), 125000n);
  assert.equal(taxToCents('0.10', '0.125'), 1n);
  assert.equal(taxToCents('100.01', '0.125'), 1250n);
});

test('rejects invalid or out-of-bounds financial values', () => {
  assert.throws(() => moneyToCents('1.234'), /Invalid decimal/);
  assert.throws(() => taxToCents('10.00', '0.30'), /outside engine bounds/);
  assert.throws(() => taxToCents('-1.00', '0.10'), /outside engine bounds/);
});
