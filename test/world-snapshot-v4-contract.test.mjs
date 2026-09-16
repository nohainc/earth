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

test('world snapshot restricts open-order details to the authenticated House', async () => {
  const source = (await import('node:fs/promises')).readFile;
  const world = await source('cloudflare/src/world-postgres.ts', 'utf8');
  const orderQuery = world.slice(world.indexOf('SELECT o.id, i.symbol'), world.indexOf('SELECT o.id, i.symbol') + 900);
  assert.match(orderQuery, /o\.owner_economic_id/);
  assert.match(orderQuery, /owner_registry/);
  assert.match(orderQuery, /\$1::TEXT IS NOT NULL/);
});

test('world snapshot keeps residency independent from Territory governance', async () => {
  const source = (await import('node:fs/promises')).readFile;
  const world = await source('cloudflare/src/world-postgres.ts', 'utf8');
  const residencyQuery = world.slice(world.indexOf('SELECT r.territory_id'), world.indexOf('SELECT r.territory_id') + 900);
  assert.match(residencyQuery, /LEFT JOIN territory_governance/);
  assert.match(residencyQuery, /COALESCE\(g\.governing_institution_id, t\.corporation_id\)/);
  assert.match(residencyQuery, /LEFT JOIN institutions/);
});

test('world snapshot reports active corporation affiliation before residency-derived identity', async () => {
  const source = (await import('node:fs/promises')).readFile;
  const world = await source('cloudflare/src/world-postgres.ts', 'utf8');
  assert.match(world, /membership: corporation\.rows\[0\] \?/);
  assert.match(world, /corporation_id: corporation\.rows\[0\]\.id/);
});
