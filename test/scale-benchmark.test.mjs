import test from 'node:test';
import assert from 'node:assert/strict';
import { benchmarkStage, SCALE_STAGES, syntheticWorld } from '../scripts/scale-benchmark.mjs';

test('scale benchmark covers the planned population stages', () => {
  assert.deepEqual(SCALE_STAGES, [1_000, 10_000, 100_000, 1_000_000]);
});

test('synthetic worlds include realistic cross-system workload ratios', () => {
  const world = syntheticWorld(100_000);
  assert.equal(world.humans, 100_000);
  assert.equal(world.buildings, 180_000);
  assert.ok(world.marketOrders > 0);
  assert.ok(world.economicTransactions > world.marketOrders);
  assert.ok(world.notifications > 0);
  assert.ok(world.researchProjects > 0);
});

test('benchmark reports streamlined settlement and removed repair overhead separately', () => {
  const result = benchmarkStage(1_000);
  for (const key of ['streamlinedMs', 'repairBookkeepingMs', 'repairOverheadRatio', 'heapDeltaMb']) assert.equal(typeof result[key], 'number');
  assert.notEqual(result.checksums.streamlined, result.checksums.repairBookkeeping);
});
