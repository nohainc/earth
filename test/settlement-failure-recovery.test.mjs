import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { runResumableSettlementDay } from '../cloudflare/src/scheduler-postgres.ts';
import { getSettlementCursor } from '../cloudflare/src/world-clock-postgres.ts';

test('terminal settlement phase failure remains failed on the next heartbeat', async () => {
  const parentUpdates = [];
  const repository = {
    async query(sql, params = []) {
      if (sql.includes('SELECT status FROM daily_settlement_runs')) {
        return { rows: [{ status: 'running' }] };
      }
      if (sql.includes('daily_settlement_phase_runs') && sql.includes("status = 'failed'")) {
        return {
          rows: [{
            phase_id: 'buildingSettlement',
            error_message: 'terminal shard failure',
          }],
        };
      }
      if (sql.includes('UPDATE daily_settlement_runs')) {
        parentUpdates.push({ sql, params });
      }
      return { rows: [] };
    },
  };

  const result = await runResumableSettlementDay(repository, 17);

  assert.equal(result.status, 'failed');
  assert.equal(result.gameDay, 17);
  assert.equal(parentUpdates.length, 1);
  assert.match(parentUpdates[0].sql, /SET status = 'failed'/);
});

test('settlement cursor reports a failed phase even when the parent run is stale', async () => {
  const repository = {
    async query(sql) {
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '16' }] };
      }
      if (sql.includes('daily_settlement_runs')) return { rows: [] };
      if (sql.includes('daily_settlement_phase_runs')) {
        return {
          rows: [{
            phase_id: 'buildingSettlement',
            error_message: 'terminal shard failure',
          }],
        };
      }
      return { rows: [] };
    },
  };

  const cursor = await getSettlementCursor(repository, 19);

  assert.equal(cursor.status, 'FAILED');
  assert.equal(cursor.failedGameDay, 17);
  assert.equal(cursor.failedPhase, 'buildingSettlement');
  assert.equal(cursor.failedError, 'terminal shard failure');
});

test('settlement JSONB existence checks are not mistaken for repository placeholders', () => {
  const source = fs.readFileSync(
    path.resolve('cloudflare/src/corporation-tax-settlement-postgres.ts'),
    'utf8',
  );

  assert.match(source, /jsonb_exists\(snap\.rules_json/);
  assert.doesNotMatch(source, /rules_json\s*\?/);
});
