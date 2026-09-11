import test from 'node:test';
import assert from 'node:assert/strict';
import { runClosedBetaSoak } from '../scripts/run-closed-beta-soak.mjs';

test('closed-beta soak is deterministic and preserves the explicit CREDIT supply', () => {
  const options = { seed: 17, days: 30, houses: 250, acceleration: 12 };
  const first = runClosedBetaSoak(options);
  const second = runClosedBetaSoak(options);
  assert.deepEqual(first, second);
  assert.equal(first.summary.creditConserved, true);
  assert.equal(first.summary.nonNegative, true);
  assert.equal(first.history.length, options.days);
});

test('closed-beta soak exposes calibration signals and positive-feedback warnings', () => {
  const report = runClosedBetaSoak({ seed: 3, days: 180, houses: 500, acceleration: 24 });
  assert.ok(report.summary.final.market.FOOD > 0);
  assert.ok(report.summary.final.research.completed >= 0);
  assert.ok(report.summary.final.humanNeeds.averageSatisfaction >= 0);
  assert.ok(Array.isArray(report.summary.warnings));
  assert.ok(Object.hasOwn(report.summary.final, 'buildingProfitability'));
});
