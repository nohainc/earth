import test from 'node:test';
import assert from 'node:assert/strict';
import {
  toAbsoluteGameMinute,
  fromAbsoluteGameMinute,
  lastClosedGameDay,
  readAuthoritativeGameTime,
  getSettlementCursor,
} from '../cloudflare/src/world-clock-postgres.ts';
import { assertEconomyCaughtUp, SettlementCatchupBarrierError } from '../cloudflare/src/settlement-barrier-postgres.ts';

test('e2e simulation: multi-day catchup and barrier gating', async () => {
  // Scenario:
  // Server was offline or backlog accumulated.
  // Current time corresponds to Game Day 4, minute 300.
  // Closed days eligible for settlement: Day 1, Day 2, Day 3.
  // Currently settled through Day 0 (no days settled yet).

  let currentSettledDay = 0;
  const simulatedClockDay = 4;
  const simulatedClockMinute = 300;
  const totalMinutes = toAbsoluteGameMinute(simulatedClockDay, simulatedClockMinute);

  const dbState = {
    clock: {
      game_day: String(simulatedClockDay),
      game_minute: simulatedClockMinute,
      total_game_minutes: String(totalMinutes),
      genesis_at: new Date('2026-01-01T00:00:00Z'),
      server_now: new Date('2026-01-01T01:17:00Z'),
      elapsed_real_seconds: String(totalMinutes),
      real_seconds_per_game_minute: 1,
    },
    settlementRuns: new Map(), // day -> 'completed' | 'running'
  };

  const mockRepo = {
    query: async (sql, params = []) => {
      if (sql.includes('earth_get_current_game_time()')) {
        return { rows: [dbState.clock] };
      }
      if (sql.includes('daily_settlement_control')) {
        return {
          rows: [{
            id: 'WORLD',
            status: 'active',
            settled_through_game_day: String(currentSettledDay),
          }],
        };
      }
      if (sql.includes('earth_advance_settlement_cursor')) {
        const targetDay = Number(params[0]);
        if (targetDay !== currentSettledDay + 1) {
          throw new Error(`Non-contiguous advance: current=${currentSettledDay}, target=${targetDay}`);
        }
        if (dbState.settlementRuns.get(targetDay) !== 'completed') {
          throw new Error(`Day ${targetDay} not completed`);
        }
        currentSettledDay = targetDay;
        return { rows: [{ earth_advance_settlement_cursor: String(currentSettledDay) }] };
      }
      return { rows: [] };
    },
  };

  // Step 1: Initial state check
  const clock = await readAuthoritativeGameTime(mockRepo);
  assert.equal(clock.gameDay, 4);
  assert.equal(lastClosedGameDay(clock), 3);

  let cursor = await getSettlementCursor(mockRepo, clock.gameDay);
  assert.equal(cursor.settledThroughGameDay, 0);
  assert.equal(cursor.lastClosedGameDay, 3);
  assert.equal(cursor.backlogDays, 3);
  assert.equal(cursor.status, 'CATCHING_UP');

  // Step 2: Economic mutation should fail due to catch-up barrier
  await assert.rejects(
    async () => {
      await assertEconomyCaughtUp(mockRepo);
    },
    (err) => {
      assert.ok(err instanceof SettlementCatchupBarrierError);
      assert.equal(err.statusCode, 409);
      assert.equal(err.currentGameDay, 4);
      assert.equal(err.settledThroughGameDay, 0);
      assert.equal(err.lastClosedGameDay, 3);
      return true;
    },
  );

  // Step 3: Sequential catch-up loop (Day 1 -> Day 2 -> Day 3)
  const targetDay = lastClosedGameDay(clock);
  for (let day = currentSettledDay + 1; day <= targetDay; day++) {
    // Attempting to advance before day is completed fails
    await assert.rejects(async () => {
      await mockRepo.query('SELECT earth_advance_settlement_cursor($1)', [day]);
    });

    // Mark day completed and advance cursor
    dbState.settlementRuns.set(day, 'completed');
    await mockRepo.query('SELECT earth_advance_settlement_cursor($1)', [day]);
    assert.equal(currentSettledDay, day);
  }

  // Step 4: After catch-up completes, verify cursor is CURRENT
  cursor = await getSettlementCursor(mockRepo, clock.gameDay);
  assert.equal(cursor.settledThroughGameDay, 3);
  assert.equal(cursor.lastClosedGameDay, 3);
  assert.equal(cursor.backlogDays, 0);
  assert.equal(cursor.status, 'CURRENT');

  // Step 5: Economic mutation should now succeed
  const caughtUpClock = await assertEconomyCaughtUp(mockRepo);
  assert.equal(caughtUpClock.gameDay, 4);
});
