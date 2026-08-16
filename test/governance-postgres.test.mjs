import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  politicalMaturityReached,
  createProposal,
  castVote,
  challengeProposal,
  resolveConstitutionalAppeal,
} from '../cloudflare/src/governance-postgres.ts';

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

test('politicalMaturityReached evaluates game day threshold correctly', () => {
  assert.equal(politicalMaturityReached(100, 90), true);
  assert.equal(politicalMaturityReached(100, 100), true);
  assert.equal(politicalMaturityReached(80, 90), false);
  assert.equal(politicalMaturityReached(NaN, 90), false);
});

test('challengeProposal files constitutional challenge for passed proposal', async () => {
  const client = new MockDbClient({
    'SELECT details FROM world_events': { rows: [], rowCount: 0 },
    'SELECT id, institution_id, outcome, executed_at': {
      rows: [{ id: 'PROP-01', institution_id: 'INST-01', outcome: 'passed', executed_at: null, execution_status: 'ready' }],
      rowCount: 1,
    },
    'SELECT kind, status FROM institutions': { rows: [{ kind: 'CITY', status: 'active' }], rowCount: 1 },
    'SELECT w.game_day, h.political_eligibility_game_day': { rows: [{ game_day: 100, political_eligibility_game_day: 50 }], rowCount: 1 },
    'SELECT 1 FROM memberships': { rows: [{ '1': 1 }], rowCount: 1 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 100 }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const result = await challengeProposal(repo, {
    humanId: 'H-01',
    proposalId: 'PROP-01',
    reason: 'Violates municipal tax charter limits',
    correlationId: 'corr-chall-01',
  });

  assert.equal(result.ok, true);
  assert.equal(result.executionStatus, 'challenged');
});

test('resolveConstitutionalAppeal voids unconstitutional proposal', async () => {
  const client = new MockDbClient({
    'SELECT details FROM world_events': { rows: [], rowCount: 0 },
    'SELECT id, institution_id, outcome, executed_at': {
      rows: [{ id: 'PROP-01', institution_id: 'INST-01', outcome: 'passed', executed_at: null }],
      rowCount: 1,
    },
    'SELECT kind, status FROM institutions': { rows: [{ kind: 'CITY', status: 'active' }], rowCount: 1 },
    'SELECT w.game_day, h.political_eligibility_game_day': { rows: [{ game_day: 100, political_eligibility_game_day: 50 }], rowCount: 1 },
    'SELECT 1 FROM memberships': { rows: [{ '1': 1 }], rowCount: 1 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 100 }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const result = await resolveConstitutionalAppeal(repo, {
    humanId: 'H-01',
    proposalId: 'PROP-01',
    ruling: 'void',
    rationale: 'Article 4 violation',
    correlationId: 'corr-ruling-01',
  });

  assert.equal(result.ok, true);
  assert.equal(result.executionStatus, 'voided');
});
