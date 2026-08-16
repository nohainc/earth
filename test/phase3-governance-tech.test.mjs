import test from 'node:test';
import assert from 'node:assert/strict';
import { challengeProposal, executeProposal, resolveConstitutionalAppeal } from '../cloudflare/src/governance-postgres.ts';
import { listPantheonOfAchievements } from '../cloudflare/src/read-postgres.ts';

function createMockRepository(queries) {
  return {
    async transaction(callback) {
      return callback({
        async query(sql, params = []) {
          return queries(sql, params);
        },
      });
    },
    async query(sql, params = []) {
      return queries(sql, params);
    },
  };
}

test('challengeProposal puts passed proposal under constitutional injunction', async () => {
  let updatedStatus = null;
  const outboxEvents = [];
  const repo = createMockRepository((sql, params) => {
    if (sql.includes("FROM world_events WHERE event_type = 'governance.challenge_filed'")) {
      return { rows: [] };
    }
    if (sql.includes('SELECT id, institution_id, outcome, executed_at, execution_status FROM proposals')) {
      return { rows: [{ id: 'P-123', institution_id: 'INST-OUC', outcome: 'passed', executed_at: null, execution_status: 'ready' }] };
    }
    if (sql.includes('SELECT kind, status FROM institutions')) {
      return { rows: [{ kind: 'OUC', status: 'active' }] };
    }
    if (sql.includes("SELECT w.game_day, h.political_eligibility_game_day FROM world_state w JOIN humans h")) {
      return { rows: [{ game_day: 100, political_eligibility_game_day: 0 }] };
    }
    if (sql.includes('SELECT 1 FROM role_assignments')) {
      return { rows: [{ id: 'ROLE-ASSIGN' }] };
    }
    if (sql.includes("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [{ game_day: 100 }] };
    }
    if (sql.includes("UPDATE proposals SET execution_status = 'challenged'")) {
      updatedStatus = 'challenged';
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO event_outbox')) {
      outboxEvents.push(params[1]);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });

  const result = await challengeProposal(repo, {
    humanId: 'H-CITIZEN',
    proposalId: 'P-123',
    reason: 'Violates constitutional subsidiarity clause',
    correlationId: 'CHALLENGE-1',
  });

  assert.equal(result.ok, true);
  assert.equal(result.proposalId, 'P-123');
  assert.equal(result.executionStatus, 'challenged');
  assert.equal(updatedStatus, 'challenged');
  assert.deepEqual(outboxEvents, ['governance-challenge:CHALLENGE-1']);
});

test('resolveConstitutionalAppeal voids unconstitutional proposal', async () => {
  let finalOutcome = null;
  let finalStatus = null;
  const outboxEvents = [];
  const repo = createMockRepository((sql, params) => {
    if (sql.includes("FROM world_events WHERE event_type = 'governance.ruling_issued'")) {
      return { rows: [] };
    }
    if (sql.includes('SELECT id, institution_id, outcome, executed_at FROM proposals')) {
      return { rows: [{ id: 'P-123', institution_id: 'INST-OUC', outcome: 'passed', executed_at: null }] };
    }
    if (sql.includes('SELECT kind, status FROM institutions')) {
      return { rows: [{ kind: 'OUC', status: 'active' }] };
    }
    if (sql.includes("SELECT w.game_day, h.political_eligibility_game_day FROM world_state w JOIN humans h")) {
      return { rows: [{ game_day: 100, political_eligibility_game_day: 0 }] };
    }
    if (sql.includes('SELECT 1 FROM role_assignments')) {
      return { rows: [{ id: 'ROLE-JURIST' }] };
    }
    if (sql.includes("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [{ game_day: 100 }] };
    }
    if (sql.includes("UPDATE proposals SET outcome = 'rejected', execution_status = 'skipped'")) {
      finalOutcome = 'rejected';
      finalStatus = 'voided';
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO event_outbox')) {
      outboxEvents.push(params[1]);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });

  const result = await resolveConstitutionalAppeal(repo, {
    humanId: 'H-JUSTICE',
    proposalId: 'P-123',
    ruling: 'void',
    rationale: 'Exceeds central jurisdiction authority',
    correlationId: 'RULING-1',
  });

  assert.equal(result.ok, true);
  assert.equal(result.ruling, 'void');
  assert.equal(result.executionStatus, 'voided');
  assert.equal(finalOutcome, 'rejected');
  assert.equal(finalStatus, 'voided');
  assert.deepEqual(outboxEvents, ['governance-ruling:RULING-1']);
});

test('executeProposal blocks execution when under challenge', async () => {
  const repo = createMockRepository((sql, params) => {
    if (sql.includes('SELECT * FROM proposals WHERE id = $1')) {
      return {
        rows: [
          {
            id: 'P-123',
            institution_id: 'INST-OUC',
            outcome: 'passed',
            executed_at: null,
            execution_status: 'challenged',
          },
        ],
      };
    }
    return { rows: [], rowCount: 1 };
  });

  await assert.rejects(
    () => executeProposal(repo, { proposalId: 'P-123', humanId: 'H-DELEGATE' }),
    /Proposal is currently under constitutional challenge/
  );
});

test('listPantheonOfAchievements returns historical deceased pantheon and living legends', async () => {
  const repo = createMockRepository((sql) => {
    if (sql.includes('FROM deceased_profiles')) {
      return {
        rows: [
          { human_id: 'H-LEGEND-1', display_name: 'Dr. John Doe', final_legacy: 250, final_standing: 100 },
        ],
      };
    }
    if (sql.includes('FROM humans WHERE life_status')) {
      return {
        rows: [
          { id: 'H-LIVING-1', display_name: 'Founder Alice', age_years: 65, standing: 80, legacy: 120, composite_legacy_score: 6930 },
        ],
      };
    }
    return { rows: [] };
  });

  const pantheon = await listPantheonOfAchievements(repo);
  assert.equal(pantheon.deceasedPantheon.length, 1);
  assert.equal(pantheon.deceasedPantheon[0].display_name, 'Dr. John Doe');
  assert.equal(pantheon.livingLeaders.length, 1);
  assert.equal(pantheon.livingLeaders[0].display_name, 'Founder Alice');
});
