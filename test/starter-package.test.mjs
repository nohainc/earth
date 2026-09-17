import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateStarterPackage, STARTER_PACKAGE_V2 } from '../cloudflare/src/starter-package.ts';

test('starter package is fixed and provides bootstrap resources for V5 Alpha', () => {
  assert.deepEqual(calculateStarterPackage(), STARTER_PACKAGE_V2);
  assert.equal(STARTER_PACKAGE_V2.design.survivalDays, 14);
  assert.equal(STARTER_PACKAGE_V2.design.marketParticipation, true);
  assert.ok(STARTER_PACKAGE_V2.resources.material >= 120);
  assert.ok(STARTER_PACKAGE_V2.resources.components >= 10);
  assert.ok(STARTER_PACKAGE_V2.resources.compute >= 5);
  assert.ok(STARTER_PACKAGE_V2.resources.energy >= 10);
  assert.ok(STARTER_PACKAGE_V2.resources.food >= 14);
});
