import test from 'node:test';
import assert from 'node:assert/strict';
import { runSimulation } from '../simulation.js';

test('Economic Simulation Invariant Stress Testing across 100 Game Days', () => {
  const result = runSimulation({ days: 100, humans: 30, seed: 12345 });

  assert.equal(result.days, 100);
  assert.equal(result.creditsConserved, true);
  assert.equal(result.nonNegativeBalances, true);
  assert.equal(result.resourceNonNegative, true);
  assert.equal(result.institutionBalancesNonNegative, true);
  assert.equal(result.boundedMachineCondition, true);
});
