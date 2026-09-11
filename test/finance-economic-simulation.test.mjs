import test from 'node:test';
import assert from 'node:assert/strict';
import { runFinanceSimulation } from '../simulation.js';

test('Finance V2 mixed gameplay conserves CREDIT and preserves contract invariants', () => {
  const result = runFinanceSimulation({ days: 45, humans: 10000, cities: 100, seed: 202603 });
  assert.equal(result.creditConserved, true);
  assert.equal(result.nonNegative, true);
  assert.equal(result.openingSupply + result.retired, result.closingSupply);
  assert.equal(result.bankSolventOrStressed, true);
  assert.ok(result.taxArrears >= 0);
});

test('Finance V2 simulation is deterministic under replay', () => {
  const first = runFinanceSimulation({ days: 30, humans: 2000, cities: 20, seed: 77 });
  const replay = runFinanceSimulation({ days: 30, humans: 2000, cities: 20, seed: 77 });
  assert.deepEqual(replay, first);
});
