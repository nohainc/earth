import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateStarterPackage, STARTER_PACKAGE_V2 } from '../cloudflare/src/starter-package.ts';

test('starter package is fixed and deliberately incomplete', () => {
  assert.deepEqual(calculateStarterPackage(), STARTER_PACKAGE_V2);
  assert.equal(STARTER_PACKAGE_V2.design.survivalDays, 14);
  assert.equal(STARTER_PACKAGE_V2.design.marketParticipation, true);
  assert.equal(STARTER_PACKAGE_V2.resources.components, 0);
  assert.equal(STARTER_PACKAGE_V2.resources.compute, 0);
});
