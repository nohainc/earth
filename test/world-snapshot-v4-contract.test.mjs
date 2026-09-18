import test from 'node:test';
import assert from 'node:assert/strict';
import { worldSnapshot } from '../cloudflare/src/world-postgres.ts';

test('the canonical world payload contains the V4 client gameplay read model', async () => {
  const repository = {
    async query(sql) {
      if (sql.includes('earth_get_current_game_time()') || sql.includes("FROM world_state WHERE id = 'WORLD'")) {
        return {
          rows: [{
            id: 'WORLD',
            game_day: '12',
            game_minute: 240,
            total_game_minutes: '17520',
            genesis_at: new Date('2026-01-01T00:00:00Z'),
            server_now: new Date('2026-01-01T04:00:00Z'),
            elapsed_real_seconds: '17520',
            real_seconds_per_game_minute: 1,
            world_seed: 'test',
            status: 'ACTIVE',
          }],
        };
      }
      if (sql.includes('resolved_constitution_snapshots_v5') || sql.includes('earth_resolve_effective_constitution')) {
        return {
          rows: [{
            id: 'CONST-EARTH-EARTH-D12',
            rate_bps: '100',
            market_fee_rate_bps: 100,
            transaction_tax_rate_bps: 50,
            rules_json: { 'EARTH.MARKET.TRANSACTION_TAX_RATE': '100' },
            version_ids: { 'EARTH.MARKET.TRANSACTION_TAX_RATE': 'CRV-1' },
            provenance_json: { 'EARTH.MARKET.TRANSACTION_TAX_RATE': 'EARTH' },
          }],
        };
      }
      if (sql.includes('constitutional_rule_versions_v5')) {
        return {
          rows: [{
            id: 'CRV-1',
            rule_code: 'EARTH.MARKET.TRANSACTION_TAX_RATE',
            authority_type: 'EARTH',
            authority_id: 'EARTH',
            value_json: { value: 100 },
            version: 1,
          }],
        };
      }
      if (sql.includes('FROM economic_assets')) return { rows: [{ code: 'CREDIT', asset_kind: 'CREDIT' }] };
      return { rows: [] };
    },
  };
  const snapshot = await worldSnapshot(repository, 'HUMAN-1', 'HOUSE-1');
  assert.equal(snapshot.clock.day, 12);
  assert.equal(snapshot.clock.minute, 240);
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
