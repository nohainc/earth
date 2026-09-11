import test from 'node:test';
import assert from 'node:assert/strict';
import { ECONOMY_SIMULATION_PROFILES, runEconomySimulation } from '../simulation.js';

test('Economy V2 scenarios are deterministic and conserve CREDIT', () => {
  for (const houses of [ECONOMY_SIMULATION_PROFILES.small, 1_000]) {
    const first = runEconomySimulation({ days: 365, houses, seed: 101, scenario: 'baseline' });
    const replay = runEconomySimulation({ days: 365, houses, seed: 101, scenario: 'baseline' });
    assert.deepEqual(replay, first);
    assert.equal(first.creditConserved, true);
    assert.ok(first.totalShortage >= 0);
    assert.ok(Object.values(first.resources).every((value) => value >= 0));
  }
});

test('Economy V2 exposes scenario differences instead of a single forecast', () => {
  const baseline = runEconomySimulation({ days: 365, houses: 100, seed: 7, scenario: 'baseline' });
  const shortage = runEconomySimulation({ days: 365, houses: 100, seed: 7, scenario: 'high-energy-shortage' });
  const technology = runEconomySimulation({ days: 365, houses: 100, seed: 7, scenario: 'technology-heavy' });
  assert.notEqual(shortage.totalShortage, baseline.totalShortage);
  assert.notEqual(technology.completedResearch, baseline.completedResearch);
  assert.equal(shortage.creditConserved, true);
});
