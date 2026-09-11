import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateMortalityHazard, stableMortalityRoll } from '../cloudflare/src/lifecycle-postgres.ts';

const healthy = {
  age: 75,
  lifeConditionScore: 100,
  recentFoodShortfallDays: 0,
  recentMissedMaintenanceDays: 0,
  healthServiceCoverage: 1,
  essentialServicesIndex: 1,
};

test('mortality hazard responds to actual life and service conditions', () => {
  const deprived = calculateMortalityHazard({
    ...healthy,
    lifeConditionScore: 35,
    recentFoodShortfallDays: 5,
    recentMissedMaintenanceDays: 4,
    healthServiceCoverage: 0.2,
    essentialServicesIndex: 0.4,
  });
  assert.ok(deprived > calculateMortalityHazard(healthy));
});

test('mortality hazard remains age-gated and bounded', () => {
  assert.equal(calculateMortalityHazard({ ...healthy, age: 64 }), 0);
  assert.equal(calculateMortalityHazard({ ...healthy, age: 105 }), 1);
  assert.ok(calculateMortalityHazard({ ...healthy, age: 90 }) <= 0.95);
});

test('mortality roll is stable and uses the complete world seed identity', () => {
  const first = stableMortalityRoll('world-a', 'H-ABC', 3);
  assert.equal(first, stableMortalityRoll('world-a', 'H-ABC', 3));
  assert.notEqual(first, stableMortalityRoll('world-b', 'H-ABC', 3));
  assert.notEqual(first, stableMortalityRoll('world-a', 'H-ABD', 3));
  assert.notEqual(first, stableMortalityRoll('world-a', 'H-ABC', 4));
  assert.ok(first >= 0 && first < 1);
});
