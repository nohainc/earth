import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  politicalMaturityReached,
  createProposal,
  castVote,
  challengeProposal,
  resolveConstitutionalAppeal,
  resolveProposalsInTransaction,
  evaluateProposalVote,
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

test('proposal resolution counts only active members of its own institution', async () => {
  const client = new MockDbClient({
    "SELECT genesis_at, simulated_day_offset FROM world_state": {
      rows: [{ genesis_at: new Date(Date.now() - 20 * 86400000).toISOString(), simulated_day_offset: 0 }],
      rowCount: 1,
    },
    "SELECT id, institution_id, quorum, approval_threshold, eligible_voter_count FROM proposals WHERE decision_status": {
      rows: [{ id: 'CITY-VOTE-1', institution_id: 'CITY-1', quorum: '0.25', approval_threshold: '0.5', eligible_voter_count: null }],
      rowCount: 1,
    },
    'SELECT support_weight, oppose_weight, abstain_weight, voter_count FROM proposal_vote_totals': {
      rows: [{ support_weight: '1', oppose_weight: '0', abstain_weight: '0', voter_count: '1' }],
      rowCount: 1,
    },
    'SELECT COUNT(DISTINCT human_id) AS count FROM ballots': {
      rows: [{ count: '1' }],
      rowCount: 1,
    },
    'JOIN institutions i ON i.id = $1': {
      rows: [{ count: '1' }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const resolved = await resolveProposalsInTransaction(repo);

  assert.equal(resolved, 1);
  const electorateQuery = client.calls.find((call) =>
    call.sql.includes('JOIN institutions i ON i.id = $1'));
  assert.ok(electorateQuery);
  assert.match(electorateQuery.sql, /i\.kind = 'CITY' AND m\.city_id = \$1/);
  assert.match(electorateQuery.sql, /i\.kind = 'CORPORATION' AND m\.corporation_id = \$1/);
  const resolution = client.calls.find((call) =>
    call.sql.startsWith('UPDATE proposals SET outcome'));
  assert.equal(resolution.params[0], 'passed');
});

test('proposal quorum uses human participation, while approval uses weighted votes', () => {
  assert.equal(evaluateProposalVote({
    voters: 13, eligibleHumans: 100, supportWeight: 26, opposeWeight: 0,
    quorum: 0.25, approvalThreshold: 0.5,
  }).quorumMet, false);
  assert.equal(evaluateProposalVote({
    voters: 25, eligibleHumans: 100, supportWeight: 25, opposeWeight: 0,
    quorum: 0.25, approvalThreshold: 0.5,
  }).passed, true);
  assert.equal(evaluateProposalVote({
    voters: 100, eligibleHumans: 100, supportWeight: 60, opposeWeight: 40,
    quorum: 0.25, approvalThreshold: 0.6,
  }).passed, true);
});

test('challengeProposal files constitutional challenge for passed proposal', async () => {
  const client = new MockDbClient({
    'SELECT details FROM world_events': { rows: [], rowCount: 0 },
    'SELECT id, institution_id, outcome, executed_at': {
      rows: [{ id: 'PROP-01', institution_id: 'INST-01', outcome: 'passed', executed_at: null, execution_status: 'ready' }],
      rowCount: 1,
    },
    'SELECT kind, status FROM institutions': { rows: [{ kind: 'CITY', status: 'active' }], rowCount: 1 },
    'SELECT id, life_status FROM humans': { rows: [{ id: 'H-01', life_status: 'active' }], rowCount: 1 },
    'SELECT city_id FROM memberships': { rows: [{ city_id: 'INST-01' }], rowCount: 1 },
    'SELECT 1 FROM memberships': { rows: [{ '1': 1 }], rowCount: 1 },
    'SELECT 1 FROM proposal_challenge_authorities': { rows: [{ '1': 1 }], rowCount: 1 },
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
    'SELECT id, life_status FROM humans': { rows: [{ id: 'H-01', life_status: 'active' }], rowCount: 1 },
    'SELECT city_id FROM memberships': { rows: [{ city_id: 'INST-01' }], rowCount: 1 },
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

test('createProposal associates typed building_catalog target', async () => {
  const client = new MockDbClient({
    'SELECT * FROM proposals WHERE institution_id = $1 AND correlation_id = $2': { rows: [], rowCount: 0 },
    'SELECT id, quorum_threshold': {
      rows: [{ id: 'GOV-C1-v1', quorum_threshold: '0.25', approval_threshold: '0.5', voting_period_days: 7, implementation_delay_days: 1 }],
      rowCount: 1,
    },
    'SELECT kind, status FROM institutions': { rows: [{ id: 'CITY-1', kind: 'CITY', status: 'active' }], rowCount: 1 },
    'SELECT game_day, game_minute': {
      rows: [{ game_day: 10, game_minute: 100, genesis_at: new Date(Date.now() - 10 * 86400000).toISOString(), simulated_day_offset: 0 }],
      rowCount: 1,
    },
    'SELECT id FROM building_catalog': {
      rows: [{ id: 'fusion-plant-t1' }],
      rowCount: 1,
    },
    'SELECT id, life_status FROM humans': { rows: [{ id: 'H-01', life_status: 'active' }], rowCount: 1 },
    'SELECT city_id FROM memberships': { rows: [{ city_id: 'CITY-1' }], rowCount: 1 },
    'SELECT 1 FROM memberships': { rows: [{ '1': 1 }], rowCount: 1 },
    'SELECT * FROM proposals WHERE id = $1': {
      rows: [{ id: 'PROP-01', target_kind: 'building_catalog', building_catalog_id: 'fusion-plant-t1' }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const res = await createProposal(repo, {
    humanId: 'H-01',
    institutionId: 'CITY-1',
    title: 'Commission Fusion Plant',
    body: 'Increase energy capacity.',
    targetCategory: 'megaproject_procurement',
    targetValue: { buildingType: 'fusion-plant' },
    correlationId: 'corr-fusion-1',
  });

  assert.equal(res.ok, true);
  const insertCall = client.calls.find((c) => c.sql.startsWith('INSERT INTO proposals'));
  assert.ok(insertCall);
  // targetKind should be 'building_catalog'
  assert.equal(insertCall.params[13], 'building_catalog');
  // building_catalog_id should be 'fusion-plant-t1'
  assert.equal(insertCall.params[14], 'fusion-plant-t1');
  // research_project_id should be null
  assert.equal(insertCall.params[15], null);
});
