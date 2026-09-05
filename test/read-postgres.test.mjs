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
    'FROM corporation_technology_projects': { rows: [{ id: 'PROJECT-1', corporation_id: 'CORP-001' }], rowCount: 1 },
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
    'SELECT * FROM communities': { rows: [{ id: 'COM-01', name: 'Sol' }], rowCount: 1 },
    'SELECT * FROM cities': { rows: [{ id: 'CITY-01', name: 'Neo' }], rowCount: 1 },
    'SELECT * FROM corporations': { rows: [{ id: 'CORP-01', name: 'Cyber' }], rowCount: 1 },
    'SELECT * FROM memberships': { rows: [], rowCount: 0 },
    'SELECT * FROM budgets': { rows: [], rowCount: 0 },
    'SELECT owner_id AS human_id, balance': { rows: [{ human_id: 'H-01', balance: 5000 }], rowCount: 1 },
    'SELECT id, residents, treasury': { rows: [], rowCount: 0 },
    'SELECT id, member_count, treasury': { rows: [], rowCount: 0 },
    'SELECT id, name, owner_id, progress FROM technologies': { rows: [], rowCount: 0 },
  });
  const repo = new PostgresRepository(client);

  const inst = await listInstitutions(repo);
  assert.equal(inst.community.length, 1);
  assert.equal(inst.city.length, 1);

  const rank = await listRankings(repo);
  assert.equal(rank.wealth.length, 1);
});
