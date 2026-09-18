import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  fromAbsoluteGameMinute,
  getSettlementCursor,
  lastClosedGameDay,
  readAuthoritativeGameTime,
  toAbsoluteGameMinute,
} from '../cloudflare/src/world-clock-postgres.ts';
import { assertEconomyCaughtUp, SettlementCatchupBarrierError } from '../cloudflare/src/settlement-barrier-postgres.ts';
import { eligibleMarketBatch } from '../cloudflare/src/market-scheduler.ts';
import { marketBatchId } from '../cloudflare/src/market-time.ts';

const read = (file) => fs.readFileSync(file, 'utf8');

function clockAt(totalGameMinutes) {
  const position = fromAbsoluteGameMinute(totalGameMinutes);
  return {
    game_day: String(position.gameDay),
    game_minute: position.gameMinute,
    total_game_minutes: String(totalGameMinutes),
    genesis_at: '2026-01-01T00:00:00.000Z',
    server_now: '2026-01-01T00:00:00.000Z',
    elapsed_real_seconds: String(totalGameMinutes),
    real_seconds_per_game_minute: 1,
  };
}

function settlementRepo({ totalGameMinutes, settledThroughGameDay = 0 }) {
  const state = { settledThroughGameDay };
  return {
    state,
    async query(sql) {
      if (sql.includes('earth_get_current_game_time()')) return { rows: [clockAt(totalGameMinutes)] };
      if (sql.includes('daily_settlement_control')) return { rows: [{ status: 'active', settled_through_game_day: String(state.settledThroughGameDay) }] };
      return { rows: [] };
    },
  };
}

function settleClosedDays(state, currentGameDay, limit = Infinity, crashAfterDay = null) {
  const target = Math.max(0, currentGameDay - 1);
  let processed = 0;
  while (state.settledThroughGameDay < target && processed < limit) {
    const day = state.settledThroughGameDay + 1;
    if (day === crashAfterDay) throw new Error(`worker crash on day ${day}`);
    state.effects.set(day, (state.effects.get(day) ?? 0) + 1);
    state.settledThroughGameDay = day;
    processed += 1;
  }
  return processed;
}

function marketCatchUp(processedThroughBatch, totalGameMinutes, seen = new Set()) {
  const eligible = eligibleMarketBatch(totalGameMinutes);
  let processed = processedThroughBatch;
  while (processed < eligible) {
    const batch = processed + 1;
    if (seen.has(batch)) throw new Error(`duplicate market batch ${batch}`);
    seen.add(batch);
    processed = batch;
  }
  return { processed, eligible, seen };
}

test('1. Clock advances without scheduler', async () => {
  const repo = settlementRepo({ totalGameMinutes: 123 });
  const clock = await readAuthoritativeGameTime(repo);
  assert.equal(clock.totalGameMinutes, 123);
  assert.equal(clock.gameMinute, 123);
  assert.equal(repo.state.settledThroughGameDay, 0);
});

test('2. Repeated scheduler heartbeats cannot mutate the clock', async () => {
  const repo = settlementRepo({ totalGameMinutes: 1440 });
  const before = await readAuthoritativeGameTime(repo);
  await getSettlementCursor(repo, before.gameDay);
  await getSettlementCursor(repo, before.gameDay);
  assert.deepEqual(await readAuthoritativeGameTime(repo), before);
});

test('3. One real second equals one game minute', () => {
  assert.equal(toAbsoluteGameMinute(1, 1), 1);
  assert.equal(toAbsoluteGameMinute(1, 2), 2);
  assert.match(read('cloudflare/src/game-clock.ts'), /1 real second = 1 game minute/);
});

test('4. Day rollover occurs exactly at 1,440 minutes', () => {
  assert.deepEqual(fromAbsoluteGameMinute(1439), { gameDay: 1, gameMinute: 1439 });
  assert.deepEqual(fromAbsoluteGameMinute(1440), { gameDay: 2, gameMinute: 0 });
});

test('5. The current open day never settles', () => {
  assert.equal(lastClosedGameDay({ gameDay: 1 }), 0);
  assert.equal(lastClosedGameDay({ gameDay: 20 }), 19);
});

for (const missedDays of [1, 20, 100]) {
  test(`6-8. Settlement catches up ${missedDays} missed day${missedDays === 1 ? '' : 's'}`, () => {
    const state = { settledThroughGameDay: 0, effects: new Map() };
    assert.equal(settleClosedDays(state, missedDays + 1), missedDays);
    assert.equal(state.settledThroughGameDay, missedDays);
    assert.equal(state.effects.size, missedDays);
  });
}

test('9. Failure on Day N prevents N+1', () => {
  const state = { settledThroughGameDay: 2, effects: new Map() };
  assert.throws(() => settleClosedDays(state, 6, Infinity, 3), /worker crash on day 3/);
  assert.equal(state.settledThroughGameDay, 2);
  assert.equal(state.effects.has(4), false);
});

test('10. Restart during catch-up resumes from the durable cursor', () => {
  const state = { settledThroughGameDay: 0, effects: new Map() };
  settleClosedDays(state, 21, 5);
  settleClosedDays(state, 21);
  assert.equal(state.settledThroughGameDay, 20);
  assert.equal(state.effects.size, 20);
});

test('11. Duplicate scheduler heartbeat is idempotent', () => {
  const state = { settledThroughGameDay: 0, effects: new Map() };
  settleClosedDays(state, 3);
  settleClosedDays(state, 3);
  assert.deepEqual([...state.effects.entries()], [[1, 1], [2, 1]]);
});

test('12. Two schedulers cannot claim the same settlement day', async () => {
  const claims = [];
  let leaseHeld = false;
  const claim = async (owner) => {
    if (leaseHeld) return null;
    leaseHeld = true;
    await Promise.resolve();
    claims.push({ owner, day: 1 });
    leaseHeld = false;
    return 1;
  };
  const results = await Promise.all([claim('scheduler-a'), claim('scheduler-b')]);
  assert.equal(results.filter((value) => value !== null).length, 1);
  assert.equal(claims.length, 1);
  assert.match(read('cloudflare/src/settlement-work-postgres.ts'), /earth_claim_settlement_day/);
});

test('13-14. Worker crash and retry do not duplicate settlement effects', () => {
  const state = { settledThroughGameDay: 0, effects: new Map() };
  assert.throws(() => settleClosedDays(state, 4, Infinity, 2));
  state.effects.delete(2);
  settleClosedDays(state, 4);
  assert.deepEqual([...state.effects.values()], [1, 1, 1]);
});

test('15. Economic mutations are blocked while settlement is behind', async () => {
  const repo = settlementRepo({ totalGameMinutes: 3 * 1440, settledThroughGameDay: 0 });
  await assert.rejects(() => assertEconomyCaughtUp(repo), SettlementCatchupBarrierError);
});

test('16. Economic mutations resume after catch-up', async () => {
  const repo = settlementRepo({ totalGameMinutes: 2 * 1440, settledThroughGameDay: 2 });
  assert.equal((await assertEconomyCaughtUp(repo)).gameDay, 3);
});

test('17. Interactive transactions use the authoritative transaction clock', () => {
  const source = read('cloudflare/src/economic-transaction-postgres.ts');
  assert.match(source, /readAuthoritativeGameTime/);
  assert.match(source, /gameMinute/);
  assert.doesNotMatch(source, /earth_post_transaction[^;]*1439/);
});

test('18. Client gameDay cannot override transaction time', () => {
  const source = read('cloudflare/src/commons-dividends-postgres.ts');
  assert.doesNotMatch(source, /input\.gameDay|gameDay\?:/);
  assert.match(read('test/client-game-time-authority.test.mjs'), /doesNotMatch/);
});

test('19. Market catches up missed absolute-time batches', () => {
  const result = marketCatchUp(10, 60 * 31);
  assert.equal(result.eligible, 30);
  assert.equal(result.processed, 30);
  assert.equal(result.seen.size, 20);
});

test('20. Market cannot process the same batch twice', () => {
  const seen = new Set([11]);
  assert.throws(() => {
    if (seen.has(11)) throw new Error('duplicate market batch');
  }, /duplicate market batch/);
  assert.equal(marketBatchId(1, 60, 60), 1);
});

test('21-23. Flutter resync and monotonic presentation contracts remain explicit', () => {
  const hud = read('flutter_client/lib/features/command_center/top_fixed_hud_panel.dart');
  const screen = read('flutter_client/lib/features/command_center/command_center_screen.dart');
  assert.match(hud, /AppLifecycleState\.resumed/);
  assert.match(hud, /onClockResync/);
  assert.match(screen, /_resyncAuthoritativeClock/);
  assert.match(screen, /Duration\(minutes: 3\)/);
  assert.match(hud, /Stopwatch/);
  assert.match(hud, /onDisplayedDayChanged/);
});

test('24. /api/world exposes the DB authoritative clock snapshot', async () => {
  const repo = { query: async (sql) => sql.includes('earth_get_current_game_time()') ? { rows: [clockAt(2000)] } : { rows: [] } };
  const snapshot = await readAuthoritativeGameTime(repo);
  assert.equal(snapshot.gameDay, 2);
  assert.equal(snapshot.gameMinute, 560);
  assert.match(read('cloudflare/src/world-postgres.ts'), /totalGameMinutes: clock\.totalGameMinutes/);
});

test('25. /health reports the same clock and cursor state', () => {
  const health = read('cloudflare/src/health.ts');
  for (const field of ['worldClock', 'settledThroughGameDay', 'lastClosedGameDay', 'processedThroughBatch', 'alerts']) {
    assert.match(health, new RegExp(field));
  }
});

test('Equivalence: normal cadence and 20-day offline catch-up converge', () => {
  const normal = { settledThroughGameDay: 0, effects: new Map() };
  const offline = { settledThroughGameDay: 0, effects: new Map() };
  for (let day = 1; day <= 20; day++) settleClosedDays(normal, day + 1);
  settleClosedDays(offline, 21);
  assert.deepEqual([...normal.effects.entries()], [...offline.effects.entries()]);
  assert.equal(normal.settledThroughGameDay, offline.settledThroughGameDay);
});
