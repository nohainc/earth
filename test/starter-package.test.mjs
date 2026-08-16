import test from 'node:test';
import assert from 'node:assert/strict';
import { boundedIndex, calculateStarterPackage, economicStartIndex } from '../cloudflare/src/starter-package.ts';

test('starter indices stay inside engine bounds', () => {
  assert.equal(boundedIndex(-10), 0.5);
  assert.equal(boundedIndex(99), 3);
  assert.equal(boundedIndex('not-a-number'), 1);
  assert.equal(economicStartIndex(25), 0.5);
  assert.equal(economicStartIndex(150), 3);
});

test('starter package scales living and productive reserves independently', () => {
  assert.deepEqual(calculateStarterPackage(1.5, 2), {
    livingCostIndex: 1.5,
    economicStartIndex: 2,
    credits: 27630,
    resources: { material: 840, components: 172, energy: 138, compute: 128 },
  });
});
