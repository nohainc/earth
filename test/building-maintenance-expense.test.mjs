import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8');

test('building operating expense uses the canonical integer-unit path', () => {
  assert.match(source, /operating_credit_units/);
  assert.match(source, /nonNegativeUnits/);
  assert.match(source, /building-settlement-v4/);
  assert.doesNotMatch(source, /maintenance_debt|repair_debt|building_repair|wear/);
});

test('operating requirements are settled from integer resource balances', () => {
  assert.match(source, /const utilization = utilizationFor/);
  assert.match(source, /const credit = \(nonNegativeUnits\(building\.operating_credit_units\) \* utilization \* ageBurden\(building, day\)\) \/ 100000000n/);
  assert.match(source, /delta: -credit/);
});
