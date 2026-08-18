import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateAnnualMortalityHazard } from '../cloudflare/src/lifecycle-postgres.ts';

test('calculateAnnualMortalityHazard returns 0 for young and prime adults (< 65)', () => {
  assert.equal(calculateAnnualMortalityHazard(20, 100, 0.68), 0);
  assert.equal(calculateAnnualMortalityHazard(35, 80, 0.68), 0);
  assert.equal(calculateAnnualMortalityHazard(50, 40, 0.68), 0);
  assert.equal(calculateAnnualMortalityHazard(64, 20, 0.68), 0);
});

test('calculateAnnualMortalityHazard scales with age and health past 65', () => {
  const hazardHealthy65 = calculateAnnualMortalityHazard(65, 90, 0.68);
  const hazardSick65 = calculateAnnualMortalityHazard(65, 30, 0.68);
  assert.ok(hazardSick65 > hazardHealthy65, 'Sick citizens have higher hazard rate');

  const hazard75 = calculateAnnualMortalityHazard(75, 80, 0.68);
  const hazard85 = calculateAnnualMortalityHazard(85, 80, 0.68);
  assert.ok(hazard85 > hazard75, 'Older citizens have higher hazard rate');
});

test('calculateAnnualMortalityHazard returns 1.0 for centenarians (>= 105)', () => {
  assert.equal(calculateAnnualMortalityHazard(105, 100, 0.68), 1.0);
  assert.equal(calculateAnnualMortalityHazard(110, 80, 0.68), 1.0);
});
