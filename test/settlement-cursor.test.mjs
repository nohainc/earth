import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { getSettlementCursor, lastClosedGameDay } from '../cloudflare/src/world-clock-postgres.ts';
import { assertEconomyCaughtUp, SettlementCatchupBarrierError } from '../cloudflare/src/settlement-barrier-postgres.ts';

test('getSettlementCursor calculates backlog correctly against lastClosedGameDay', async () => {
  // Current game day 5: last closed day is 4
  // Settled through day 2: backlog is 2 days (Day 3, Day 4)
  const repoCatchingUp = {
    query: async (sql) => {
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '2' }] };
      }
      return { rows: [] };
    },
  };

  const cursorCatchingUp = await getSettlementCursor(repoCatchingUp, 5);
  assert.equal(cursorCatchingUp.settledThroughGameDay, 2);
  assert.equal(cursorCatchingUp.lastClosedGameDay, 4);
  assert.equal(cursorCatchingUp.backlogDays, 2);
  assert.equal(cursorCatchingUp.status, 'CATCHING_UP');

  // Current game day 5: settled through day 4: backlog is 0, status is CURRENT
  const repoCurrent = {
    query: async (sql) => {
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '4' }] };
      }
      return { rows: [] };
    },
  };

  const cursorCurrent = await getSettlementCursor(repoCurrent, 5);
  assert.equal(cursorCurrent.settledThroughGameDay, 4);
  assert.equal(cursorCurrent.lastClosedGameDay, 4);
  assert.equal(cursorCurrent.backlogDays, 0);
  assert.equal(cursorCurrent.status, 'CURRENT');

  // Paused status reflection
  const repoPaused = {
    query: async (sql) => {
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'paused', settled_through_game_day: '2' }] };
      }
      return { rows: [] };
    },
  };

  const cursorPaused = await getSettlementCursor(repoPaused, 5);
  assert.equal(cursorPaused.status, 'PAUSED');
});

test('assertEconomyCaughtUp enforces settlement barrier for economic mutations', async () => {
  // Caught up: currentGameDay 3, settledThrough 2 -> succeeds
  const caughtUpRepo = {
    query: async (sql) => {
      if (sql.includes('earth_get_current_game_time()')) {
        return {
          rows: [{
            game_day: '3',
            game_minute: 100,
            total_game_minutes: '2980',
            genesis_at: new Date('2026-01-01T00:00:00Z'),
            server_now: new Date('2026-01-01T00:49:40Z'),
            elapsed_real_seconds: '2980',
            real_seconds_per_game_minute: 1,
          }],
        };
      }
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '2' }] };
      }
      return { rows: [] };
    },
  };

  const clock = await assertEconomyCaughtUp(caughtUpRepo);
  assert.equal(clock.gameDay, 3);

  // Behind: currentGameDay 5, settledThrough 2 -> throws SettlementCatchupBarrierError (HTTP 409)
  const behindRepo = {
    query: async (sql) => {
      if (sql.includes('earth_get_current_game_time()')) {
        return {
          rows: [{
            game_day: '5',
            game_minute: 0,
            total_game_minutes: '5760',
            genesis_at: new Date('2026-01-01T00:00:00Z'),
            server_now: new Date('2026-01-01T01:36:00Z'),
            elapsed_real_seconds: '5760',
            real_seconds_per_game_minute: 1,
          }],
        };
      }
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '2' }] };
      }
      return { rows: [] };
    },
  };

  await assert.rejects(
    async () => {
      await assertEconomyCaughtUp(behindRepo);
    },
    (err) => {
      assert.ok(err instanceof SettlementCatchupBarrierError);
      assert.equal(err.statusCode, 409);
      assert.equal(err.code, 'WORLD_SETTLEMENT_CATCHING_UP');
      assert.equal(err.currentGameDay, 5);
      assert.equal(err.settledThroughGameDay, 2);
      assert.equal(err.lastClosedGameDay, 4);
      return true;
    },
  );
});

test('settlement cursor SQL prevents non-contiguous advancement and requires completed status', () => {
  const sql = fs.readFileSync(path.resolve('db/migrations/130_authoritative_world_clock.sql'), 'utf8');
  assert.match(sql, /IF p_completed_game_day <> v_current_cursor \+ 1 THEN/);
  assert.match(sql, /non-contiguous settlement/);
  assert.match(sql, /IF v_day_status <> 'completed' THEN/);
  assert.match(sql, /daily_settlement_control/);
  assert.match(sql, /FOR UPDATE/);
});
