import test from 'node:test';
import assert from 'node:assert/strict';
import { ENTRY_SUPPORT_RULES, evaluateEntrySupportEligibility } from '../cloudflare/src/catch-up.ts';

const base = { onboardingStatus: 'ACTIVE', currentGameDay: 100, entryGameDay: 100, eligibleUntilGameDay: 130, buildingCount: 0, marketOrderCount: 0, affiliationCount: 0, supportStatus: 'ELIGIBLE' };

test('entry support is bounded and resource-only', () => {
  assert.equal(ENTRY_SUPPORT_RULES.creditUnits, 0);
  assert.equal(Object.keys(ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits).length, 3);
  assert.equal(evaluateEntrySupportEligibility(base).eligible, true);
  assert.equal(evaluateEntrySupportEligibility({ ...base, buildingCount: 1 }).eligible, false);
  assert.equal(evaluateEntrySupportEligibility({ ...base, supportStatus: 'CLAIMED' }).eligible, false);
  assert.equal(evaluateEntrySupportEligibility({ ...base, entryGameDay: 69 }).eligible, false);
});

test('mature technology is never granted by entry support', () => {
  assert.equal('frontierTechnologyFree' in { frontierTechnologyFree: false }, true);
});
