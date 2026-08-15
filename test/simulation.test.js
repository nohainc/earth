import test from 'node:test';
import assert from 'node:assert/strict';
import { runSimulation } from '../simulation.js';

test('synthetic EARTH economy preserves core invariants over a year', () => {
  const result = runSimulation({ days: 365, humans: 30 });
  assert.equal(result.creditsConserved, true);
  assert.equal(result.nonNegativeBalances, true);
  assert.equal(result.boundedMachineCondition, true);
  assert.equal(result.resourceNonNegative, true);
  assert.equal(result.institutionBalancesNonNegative, true);
  assert.ok(result.trades > 0);
  assert.ok(result.maintenanceDemand > 0);
  assert.ok(result.production > 0);
});

test('synthetic economy is deterministic for replay and dispute analysis', () => {
  const first = runSimulation({ days: 120, humans: 30, seed: 2026 });
  const second = runSimulation({ days: 120, humans: 30, seed: 2026 });
  assert.deepEqual(second, first);
});
