import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  listEvents,
  listNotifications,
  markNotificationRead,
  auditWorld,
  listInstitutions,
  listRankings,
  listTechnology,
  listPantheonOfAchievements,
  listCemeteryProfiles,
  listMarketPriceHistory,
} from '../cloudflare/src/read-postgres.ts';

class MockDbClient {
  constructor(handlers = {}) {
    this.handlers = handlers;
    this.calls = [];
  }

  async query(sql, params = []) {
    this.calls.push({ sql, params });
    for (const [pattern, handler] of Object.entries(this.handlers)) {
      if (sql.includes(pattern)) {
        return typeof handler === 'function' ? handler(sql, params) : handler;
      }
    }
    return { rows: [], rowCount: 0 };
  }
}

test('listNotifications queries user notifications and counts unread', async () => {
  const client = new MockDbClient({
    'SELECT id, notification_type': {
      rows: [
        { id: 'notif-1', notification_type: 'market', title: 'Order Filled', body: '50 Energy bought', read_at: null },
      ],
      rowCount: 1,
    },
    'SELECT COUNT(*)::integer AS count FROM notifications': {
      rows: [{ count: '1' }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const result = await listNotifications(repo, 'H-001', 10);
  assert.equal(result.notifications.length, 1);
  assert.equal(result.unread, 1);
});

test('listTechnology scopes corporation research to the current human', async () => {
  const client = new MockDbClient({
    'FROM corporation_research_projects p': { rows: [{ id: 'PROJECT-1', corporation_economic_id: 1001 }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const result = await listTechnology(repo, 'H-001');
  assert.equal(result.projects.length, 1);
  assert.ok(Array.isArray(result.catalog));
  assert.equal(result.patents, undefined);
  assert.equal(result.licenses, undefined);
  assert.equal(client.calls.filter((call) => call.params.includes('H-001')).length, 1);
});

test('markNotificationRead updates timestamp', async () => {
  const client = new MockDbClient({});
  const repo = new PostgresRepository(client);

  const result = await markNotificationRead(repo, 'H-001', 'notif-1');
  assert.equal(result.ok, true);
  assert.ok(client.calls.some((c) => c.sql.includes('UPDATE notifications SET read_at')));
});

test('auditWorld validates balances and membership invariants', async () => {
  const client = new MockDbClient({
    'SELECT COUNT(*)::integer AS invalid FROM account_balances': { rows: [{ invalid: '0' }], rowCount: 1 },
    'SELECT COUNT(*)::integer AS invalid FROM ledger_entries': { rows: [{ invalid: '0' }], rowCount: 1 },
    'SELECT COUNT(*)::integer AS count FROM succession_plans': { rows: [{ count: '1' }], rowCount: 1 },
    'SELECT COUNT(*)::integer AS invalid FROM corporations': { rows: [{ invalid: '0' }], rowCount: 1 },
    'SELECT COUNT(*)::integer AS invalid FROM cities': { rows: [{ invalid: '0' }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const result = await auditWorld(repo, 'H-001');
  assert.equal(result.ok, true);
  assert.equal(result.checks.balancesNonNegative, true);
  assert.equal(result.checks.ledgerEntriesValid, true);
});

test('listInstitutions and listRankings return structured models', async () => {
  const client = new MockDbClient({
    'SELECT * FROM communities': { rows: [], rowCount: 0 },
    'SELECT id, corporation_id, name, status FROM territories': { rows: [{ id: 'T-01', corporation_id: 'CORP-01', name: 'Primary Territory', status: 'ACTIVE' }], rowCount: 1 },
    'SELECT id, status FROM corporations': { rows: [{ id: 'CORP-01', status: 'ACTIVE' }], rowCount: 1 },
    'SELECT * FROM memberships': { rows: [], rowCount: 0 },
    'FROM institution_budget_lines': { rows: [], rowCount: 0 },
    'SELECT owner_id AS human_id, balance': { rows: [{ human_id: 'H-01', balance: 5000 }], rowCount: 1 },
    'FROM humans h': { rows: [{ human_id: 'H-01', balance: 5000 }], rowCount: 1 },
    'FROM owner_registry o JOIN economic_accounts': { rows: [{ human_id: 'H-01', balance: 5000 }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const inst = await listInstitutions(repo);
  assert.equal(inst.community.length, 0);
  assert.equal(inst.territories.length, 1);

  const rank = await listRankings(repo, { currentHumanId: 'H-01' });
  assert.ok(Array.isArray(rank.territories));
});

test('public memorial read models are bounded and sourced from canonical facts', async () => {
  const client = new MockDbClient({
    'SELECT * FROM earth_get_current_game_time()': { rows: [{ game_day: 100, game_minute: 0, total_game_minutes: 100 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }], rowCount: 1 },
    "WHERE h.status = 'DECEASED'": { rows: [{ human_id: 'H-DEAD', display_name: 'Ada', final_legacy: '20' }], rowCount: 1 },
    "WHERE h.status = 'ACTIVE'": { rows: [{ id: 'H-LIVE', display_name: 'Bea', composite_legacy_score: '30' }], rowCount: 1 },
    'FROM houses WHERE status': { rows: [{ id: 'HOUSE-1', house_name: 'House One' }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);
  const pantheon = await listPantheonOfAchievements(repo);
  assert.equal(pantheon.deceasedPantheon.length, 1);
  assert.equal(pantheon.livingLeaders.length, 1);
  assert.equal(pantheon.houses.length, 1);
  assert.match(client.calls[0].sql, /LIMIT \$2/);

  const cemetery = await listCemeteryProfiles(repo, { search: 'Ada', limit: 9999 });
  assert.equal(cemetery.cemetery.length, 1);
  assert.equal(cemetery.profiles, cemetery.cemetery);
  assert.equal(cemetery.cemetery[0].display_name, 'Ada');
});

test('market price history reads daily candles and clamps the requested window', async () => {
  const client = new MockDbClient({
    'FROM market_instruments i': {
      rows: [{ symbol: 'SPOT-ENERGY', period_id: '42', open_price_units: '10000', high_price_units: '12000', low_price_units: '9000', close_price_units: '11000', volume_units: '5000000', fill_count: 3 }],
      rowCount: 1,
    },
  });
  const result = await listMarketPriceHistory(new PostgresRepository(client), 'ENERGY', 9999);
  assert.equal(result.product, 'energy');
  assert.equal(result.history.length, 1);
  assert.equal(result.history[0].price, '110.00');
  assert.match(client.calls[0].sql, /interval_kind = 'daily'/);
  assert.equal(client.calls[0].params[1], 100);
});
