import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  createCommunity,
  updateCommunity,
  changeCommunityMembership,
  listCommunityMembershipRequests,
  decideCommunityMembershipRequest,
  setCommunityMemberRole,
  disbandCommunity,
  contributeToCommunity,
} from '../cloudflare/src/communities-postgres.ts';

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

test('createCommunity forms a new community with description and admission policy', async () => {
  const client = new MockDbClient({
    'SELECT institution_id FROM membership_events': { rows: [], rowCount: 0 },
    'SELECT id FROM humans': { rows: [{ id: 'H-001' }], rowCount: 1 },
    'SELECT id FROM communities WHERE lower(name)': { rows: [], rowCount: 0 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 184 }], rowCount: 1 },
    'INSERT INTO communities': { rows: [], rowCount: 1 },
    'INSERT INTO account_balances': { rows: [], rowCount: 1 },
    'INSERT INTO community_members': { rows: [], rowCount: 1 },
    'INSERT INTO membership_events': { rows: [], rowCount: 1 },
    'INSERT INTO notifications': { rows: [], rowCount: 1 },
    'SELECT * FROM communities WHERE id = $1': {
      rows: [{
        id: 'COMM-001',
        name: 'Quantum Makers Guild',
        description: 'Pioneering quantum micro-fabrication.',
        admission_policy: 'approval',
        founder_id: 'H-001',
        shared_credits: '0',
      }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const res = await createCommunity(repo, {
    founderId: 'H-001',
    name: 'Quantum Makers Guild',
    description: 'Pioneering quantum micro-fabrication.',
    admissionPolicy: 'approval',
    correlationId: 'test-corr-001',
  });

  assert.equal(res.ok, true);
  assert.equal(res.community.name, 'Quantum Makers Guild');
  assert.equal(res.community.admission_policy, 'approval');
});

test('updateCommunity updates description and admission policy for founder or admin', async () => {
  const client = new MockDbClient({
    'SELECT id, founder_id FROM communities WHERE id = $1': {
      rows: [{ id: 'COMM-001', founder_id: 'H-001' }],
      rowCount: 1,
    },
    'SELECT role FROM community_members WHERE community_id = $1 AND human_id = $2': {
      rows: [{ role: 'founder' }],
      rowCount: 1,
    },
    'UPDATE communities SET description': { rows: [], rowCount: 1 },
    'UPDATE communities SET admission_policy': { rows: [], rowCount: 1 },
    'SELECT * FROM communities WHERE id = $1': {
      rows: [{
        id: 'COMM-001',
        description: 'Updated manifesto.',
        admission_policy: 'open',
      }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const res = await updateCommunity(repo, {
    communityId: 'COMM-001',
    humanId: 'H-001',
    description: 'Updated manifesto.',
    admissionPolicy: 'open',
  });

  assert.equal(res.ok, true);
  assert.equal(res.community.description, 'Updated manifesto.');
  assert.equal(res.community.admission_policy, 'open');
});

test('changeCommunityMembership handles approval admission policy by creating a pending request', async () => {
  const client = new MockDbClient({
    'SELECT id, status, founder_id, admission_policy FROM communities': {
      rows: [{ id: 'COMM-001', status: 'active', founder_id: 'H-001', admission_policy: 'approval' }],
      rowCount: 1,
    },
    'SELECT id FROM humans': { rows: [{ id: 'H-002' }], rowCount: 1 },
    'SELECT community_id, role FROM community_members': { rows: [], rowCount: 0 },
    'SELECT id FROM community_membership_requests': { rows: [], rowCount: 0 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 184 }], rowCount: 1 },
    'INSERT INTO community_membership_requests': { rows: [], rowCount: 1 },
    'INSERT INTO notifications': { rows: [], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const res = await changeCommunityMembership(repo, {
    communityId: 'COMM-001',
    humanId: 'H-002',
    action: 'join',
  });

  assert.equal(res.ok, true);
  assert.equal(res.pendingApproval, true);
});

test('disbandCommunity succeeds when treasury is zero and fails when treasury > 0', async () => {
  // Case 1: Treasury > 0 (should fail)
  const clientWithFunds = new MockDbClient({
    'SELECT id, founder_id, shared_credits FROM communities WHERE id = $1 FOR UPDATE': {
      rows: [{ id: 'COMM-001', founder_id: 'H-001', shared_credits: '500.00' }],
      rowCount: 1,
    },
  });
  const repoWithFunds = new PostgresRepository(clientWithFunds);

  await assert.rejects(
    () => disbandCommunity(repoWithFunds, { communityId: 'COMM-001', humanId: 'H-001' }),
    /Cannot disband community with remaining shared treasury/i,
  );

  // Case 2: Treasury == 0 (should succeed)
  const clientEmpty = new MockDbClient({
    'SELECT id, founder_id, shared_credits FROM communities WHERE id = $1 FOR UPDATE': {
      rows: [{ id: 'COMM-001', founder_id: 'H-001', shared_credits: '0' }],
      rowCount: 1,
    },
    'DELETE FROM community_membership_requests': { rows: [], rowCount: 0 },
    'DELETE FROM community_members': { rows: [], rowCount: 1 },
    'DELETE FROM communities': { rows: [], rowCount: 1 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 184 }], rowCount: 1 },
    'INSERT INTO notifications': { rows: [], rowCount: 1 },
  });
  const repoEmpty = new PostgresRepository(clientEmpty);

  const res = await disbandCommunity(repoEmpty, { communityId: 'COMM-001', humanId: 'H-001' });
  assert.equal(res.ok, true);
  assert.equal(res.disbanded, true);
});

test('community contribution rejects non-positive amounts before ledger mutation', async () => {
  const client = new MockDbClient({
    "SELECT amount, game_day FROM ledger_entries": { rows: [], rowCount: 0 },
    'SELECT id, status, shared_credits FROM communities': { rows: [{ id: 'COMM-001', status: 'active', shared_credits: '0' }], rowCount: 1 },
    'SELECT human_id FROM community_members': { rows: [{ human_id: 'H-001' }], rowCount: 1 },
    "SELECT account_id, balance FROM account_balances": { rows: [{ account_id: 'account-human-H-001', balance: '100' }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);
  await assert.rejects(
    () => contributeToCommunity(repo, { communityId: 'COMM-001', humanId: 'H-001', amount: -10, correlationId: 'community-negative-1' }),
    /positive|amount|ledger/i,
  );
  assert.equal(client.calls.some((call) => call.sql.includes('UPDATE communities SET shared_credits')), false);
});
