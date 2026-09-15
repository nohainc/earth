import test from 'node:test';
import assert from 'node:assert/strict';
import { settlementBarrier } from '../cloudflare/src/settlement-barrier.ts';

const phase = (id, order, prerequisites = []) => ({ id, order, shardMode: 'all', status: 'required', prerequisites, version: 'test', execute: async () => undefined });

test('settlement barrier opens only after every required phase is complete', () => {
  const phases = [phase('opening', 1), phase('economy', 2, ['opening']), phase('close', 3, ['economy'])];
  assert.equal(settlementBarrier(phases, [
    { phaseId: 'opening', status: 'completed', shard: 0 },
    { phaseId: 'economy', status: 'completed', shard: 0 },
    { phaseId: 'close', status: 'pending', shard: 0 },
  ]).open, false);
  const complete = phases.map((item) => ({ phaseId: item.id, status: 'completed', shard: 0 }));
  assert.deepEqual(settlementBarrier(phases, complete), { open: true, requiredPhaseCount: 3, completedPhaseCount: 3, incompletePhaseIds: [] });
});
