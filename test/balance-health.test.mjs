import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateBalanceHealth } from '../simulation/balance-health.mjs';
import { runResourceEconomySimulation } from '../simulation/resource-economy-simulator.mjs';

test('balance health is deterministic and exposes quantitative bands', () => {
  const input = { houses: 100, survivingHouses: 95, shortageFrequency: .1, averageUtilization: { FOOD: .5 }, wealth: { maxToMean: 2 } };
  assert.equal(evaluateBalanceHealth(input).status, 'HEALTHY');
  assert.equal(evaluateBalanceHealth({ ...input, shortageFrequency: .4 }).status, 'REVIEW');
  const first = runResourceEconomySimulation({ houses: 100, days: 3650, seed: 99, scenario: 'baseline' });
  const second = runResourceEconomySimulation({ houses: 100, days: 3650, seed: 99, scenario: 'baseline' });
  assert.deepEqual(first, second);
  assert.ok(['HEALTHY', 'REVIEW'].includes(first.health.status));
  const century = runResourceEconomySimulation({ houses: 1000, days: 36500, seed: 42, scenario: 'baseline' });
  assert.equal(century.health.status, 'HEALTHY');
  assert.ok(century.health.creditExposureRatio <= century.health.targets.creditExposureToSupplyCeiling);
});
