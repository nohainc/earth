import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  ownershipRegistry,
  transferShares,
  proposeMerger,
} from '../cloudflare/src/business-postgres.ts';

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

test('ownershipRegistry returns ownership percentage and controller', async () => {
  const client = new MockDbClient({
    'SELECT id, name, owner_id FROM businesses WHERE id = $1': {
      rows: [{ id: 'B-01', name: 'Aether Fab', owner_id: 'H-01' }],
      rowCount: 1,
    },
    'SELECT business_shares.holder_id': {
      rows: [
        { holder_id: 'H-01', display_name: 'Amara', shares: '70' },
        { holder_id: 'H-02', display_name: 'Kaelen', shares: '30' },
      ],
      rowCount: 2,
    },
  });
  const repo = new PostgresRepository(client);

  const result = await ownershipRegistry(repo, 'B-01');
  assert.equal(result.totalIssuedShares, 100);
  assert.equal(result.controllingHumanId, 'H-01');
  assert.equal(result.holders[0].percentage, 70);
  assert.equal(result.holders[1].percentage, 30);
});

test('transferShares updates seller and buyer holdings', async () => {
  const client = new MockDbClient({
    'SELECT asset_id AS business_id': { rows: [], rowCount: 0 },
    'SELECT id FROM businesses': { rows: [{ id: 'B-01' }], rowCount: 1 },
    'SELECT id FROM humans': { rows: [{ id: 'H-02', life_status: 'active' }], rowCount: 1 },
    'SELECT shares FROM business_shares WHERE business_id = $1 AND holder_id = $2': { rows: [{ shares: '50' }], rowCount: 1 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 120 }], rowCount: 1 },
    'SELECT holder_id, shares FROM business_shares WHERE business_id = $1': {
      rows: [{ holder_id: 'H-01', shares: '25' }, { holder_id: 'H-02', shares: '25' }],
      rowCount: 2,
    },
    'INSERT INTO business_shares': { rows: [], rowCount: 1 },
    'UPDATE business_shares': { rows: [], rowCount: 1 },
    'INSERT INTO ownership_events': { rows: [], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const result = await transferShares(repo, {
    holderId: 'H-01',
    businessId: 'B-01',
    recipientId: 'H-02',
    shares: 25,
    correlationId: 'tx-001',
  });

  assert.equal(result.ok, true);
  assert.equal(result.shares, 25);
});

test('proposeMerger records tender offer', async () => {
  const client = new MockDbClient({
    'SELECT id FROM negotiated_contracts WHERE proposer_id = $1 AND correlation_id = $2': { rows: [], rowCount: 0 },
    'SELECT id, owner_id, status FROM businesses WHERE id = $1 FOR UPDATE': (sql, params) => {
      if (params[0] === 'B-01') return { rows: [{ id: 'B-01', owner_id: 'H-01', status: 'active', treasury: '50000', name: 'Acquirer Corp' }], rowCount: 1 };
      return { rows: [{ id: 'B-02', owner_id: 'H-02', status: 'active', treasury: '10000', name: 'Target Corp' }], rowCount: 1 };
    },
    'SELECT shares FROM business_shares WHERE business_id = $1': { rows: [{ shares: '100' }], rowCount: 1 },
    'SELECT account_id, balance FROM account_balances WHERE owner_id = $1': { rows: [{ account_id: 'ACC-01', balance: '50000.00' }], rowCount: 1 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 100 }], rowCount: 1 },
    'INSERT INTO negotiated_contracts': { rows: [{ id: 'MERGER-01' }], rowCount: 1 },
    'INSERT INTO outbox_events': { rows: [], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const result = await proposeMerger(repo, {
    acquirerId: 'H-01',
    acquirerBusinessId: 'B-01',
    targetBusinessId: 'B-02',
    pricePerShare: 150,
    correlationId: 'merger-offer-01',
  });

  assert.equal(result.ok, true);
  assert.match(result.mergerId, /^MERGER-/);
});
