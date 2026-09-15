import test from 'node:test';
import assert from 'node:assert/strict';
import { worldSnapshot } from '../cloudflare/src/world-postgres.ts';

test('the canonical world payload contains the V4 client gameplay read model', async () => {
  const repository = {
    async query(sql) {
      if (sql.includes("FROM world_state WHERE id = 'WORLD'")) {
        return { rows: [{ id: 'WORLD', game_day: 12, game_minute: 240, world_seed: 'test', status: 'ACTIVE' }] };
      }
      if (sql.includes('FROM economic_assets')) return { rows: [{ code: 'CREDIT', asset_kind: 'CREDIT' }] };
      return { rows: [] };
    },
  };
  const snapshot = await worldSnapshot(repository, 'HUMAN-1', 'HOUSE-1');
  assert.deepEqual(snapshot.clock, { day: 12, minute: 240 });
  assert.equal(snapshot.human, null);
  assert.deepEqual(snapshot.resources, {});
  assert.deepEqual(snapshot.buildings, []);
  assert.deepEqual(snapshot.buildingCatalog, []);
  assert.deepEqual(snapshot.finance, { balance: '0', obligations: [] });
  assert.ok(Array.isArray(snapshot.decisionQueue));
});
