import test from 'node:test';
import assert from 'node:assert/strict';
import { runSimulation } from '../simulation.js';

test('Tier 3 chaos: adversarial seeds preserve simulation invariants and replay deterministically', () => {
  const seeds = [0, 1, 7, 0x7fffffff, 0xffffffff];
  for (const seed of seeds) {
    const first = runSimulation({ days: 100, humans: 100, seed });
    const second = runSimulation({ days: 100, humans: 100, seed });
    assert.deepEqual(first, second, `seed ${seed} must be replayable`);
    assert.equal(first.creditsConserved, true, `credits leaked for seed ${seed}`);
    assert.equal(first.nonNegativeBalances, true);
    assert.equal(first.resourceNonNegative, true);
    assert.equal(first.institutionBalancesNonNegative, true);
    assert.equal(first.boundedMachineCondition, true);
  }
});

test('Tier 3 chaos: large headless run terminates with bounded state', { timeout: 10_000 }, () => {
  const result = runSimulation({ days: 100, humans: 1_000, seed: 42 });
  assert.equal(result.days, 100);
  assert.ok(result.trades >= 0);
  assert.ok(result.production >= 0);
});
