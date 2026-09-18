import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  toAbsoluteGameMinute,
  fromAbsoluteGameMinute,
  lastClosedGameDay,
  readAuthoritativeGameTime,
  getSettlementCursor,
} from '../cloudflare/src/world-clock-postgres.ts';

test('world clock invariants: 1 real second = 1 game minute, 1440 game minutes = 1 game day', () => {
  // Absolute minute 0 -> Day 1, Minute 0 (00:00)
  assert.deepEqual(fromAbsoluteGameMinute(0), { gameDay: 1, gameMinute: 0 });
  assert.equal(toAbsoluteGameMinute(1, 0), 0);

  // Absolute minute 1 -> Day 1, Minute 1 (00:01)
  assert.deepEqual(fromAbsoluteGameMinute(1), { gameDay: 1, gameMinute: 1 });
  assert.equal(toAbsoluteGameMinute(1, 1), 1);

  // Absolute minute 1439 -> Day 1, Minute 1439 (23:59)
  assert.deepEqual(fromAbsoluteGameMinute(1439), { gameDay: 1, gameMinute: 1439 });
  assert.equal(toAbsoluteGameMinute(1, 1439), 1439);

  // Absolute minute 1440 -> Day 2, Minute 0 (00:00)
  assert.deepEqual(fromAbsoluteGameMinute(1440), { gameDay: 2, gameMinute: 0 });
  assert.equal(toAbsoluteGameMinute(2, 0), 1440);

  // Absolute minute 1441 -> Day 2, Minute 1 (00:01)
  assert.deepEqual(fromAbsoluteGameMinute(1441), { gameDay: 2, gameMinute: 1 });
  assert.equal(toAbsoluteGameMinute(2, 1), 1441);

  // Day 100, Minute 720 (12:00)
  const total = toAbsoluteGameMinute(100, 720);
  assert.equal(total, 99 * 1440 + 720);
  assert.deepEqual(fromAbsoluteGameMinute(total), { gameDay: 100, gameMinute: 720 });
});

test('lastClosedGameDay invariant: current open day is never closed or settled', () => {
  assert.equal(lastClosedGameDay(1), 0); // During Day 1, Day 0 is closed (no days eligible)
  assert.equal(lastClosedGameDay(2), 1); // During Day 2, Day 1 is closed
  assert.equal(lastClosedGameDay(5), 4); // During Day 5, Day 4 is closed
  assert.equal(lastClosedGameDay({ gameDay: 10 }), 9);
});

test('readAuthoritativeGameTime maps database function results correctly', async () => {
  const mockRepo = {
    query: async (sql) => {
      if (sql.includes('earth_get_current_game_time()')) {
        return {
          rows: [{
            game_day: '5',
            game_minute: 720,
            total_game_minutes: '6480',
            genesis_at: new Date('2026-01-01T00:00:00Z'),
            server_now: new Date('2026-01-01T01:48:00Z'),
            elapsed_real_seconds: '6480',
            real_seconds_per_game_minute: 1,
          }],
        };
      }
      return { rows: [] };
    },
  };

  const clock = await readAuthoritativeGameTime(mockRepo);
  assert.equal(clock.gameDay, 5);
  assert.equal(clock.gameMinute, 720);
  assert.equal(clock.totalGameMinutes, 6480);
  assert.equal(clock.elapsedRealSeconds, 6480);
  assert.equal(clock.realSecondsPerGameMinute, 1);
  assert.equal(clock.genesisAt, '2026-01-01T00:00:00.000Z');
  assert.equal(clock.serverNow, '2026-01-01T01:48:00.000Z');
});

test('migration 130 ensures genesis_at immutability trigger and function definitions exist', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/130_authoritative_world_clock.sql'), 'utf8');
  assert.match(migration, /genesis_at TIMESTAMPTZ/);
  assert.match(migration, /trg_world_genesis_immutability/);
  assert.match(migration, /earth_guard_world_genesis_immutability/);
  assert.match(migration, /settled_through_game_day BIGINT/);
  assert.match(migration, /earth_get_current_game_time/);
  assert.match(migration, /earth_game_day_from_total_minutes/);
  assert.match(migration, /earth_absolute_game_minute/);
  assert.match(migration, /earth_advance_settlement_cursor/);
  assert.match(migration, /earth_complete_settlement_day/);
});
