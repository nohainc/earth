import test from 'node:test';
import assert from 'node:assert/strict';
import { projectGameDeadline, getEffectiveGenesisTime, getAuthoritativeGameTime } from '../cloudflare/src/game-clock.ts';

test('projects a governance deadline into game and real time', () => {
  const deadline = projectGameDeadline({
    gameDay: 100,
    gameMinute: 120,
    closesAt: '2026-08-15T00:01:40.000Z',
    nowMs: Date.parse('2026-08-15T00:00:00.000Z'),
    realSecondsPerGameMinute: 1,
  });
  assert.deepEqual(deadline, {
    gameDay: 100,
    gameMinute: 220,
    realSecondsRemaining: 100,
    closesAt: '2026-08-15T00:01:40.000Z',
  });
});

test('projects an authoritative game-time deadline without using wall-clock time', () => {
  const deadline = projectGameDeadline({
    gameDay: 100,
    gameMinute: 120,
    deadlineGameDay: 100,
    deadlineGameMinute: 220,
    closesAt: null,
    nowMs: Date.parse('2026-08-15T00:00:00.000Z'),
    realSecondsPerGameMinute: 1,
  });
  assert.equal(deadline?.gameDay, 100);
  assert.equal(deadline?.gameMinute, 220);
  assert.equal(deadline?.realSecondsRemaining, 100);
});

test('clamps expired deadlines without moving the game clock backwards', () => {
  const deadline = projectGameDeadline({
    gameDay: 100,
    gameMinute: 1439,
    closesAt: '2026-08-14T23:00:00.000Z',
    nowMs: Date.parse('2026-08-15T00:00:00.000Z'),
  });
  assert.equal(deadline?.realSecondsRemaining, 0);
  assert.equal(deadline?.gameDay, 100);
  assert.equal(deadline?.gameMinute, 1439);
});

test('rejects invalid deadlines', () => {
  assert.equal(projectGameDeadline({ gameDay: 1, gameMinute: 0, closesAt: 'invalid', nowMs: 0 }), null);
});

test('getEffectiveGenesisTime shifts start time back according to simulated day offset', () => {
  const genesis = '2026-01-01T00:00:00.000Z';
  const effective0 = getEffectiveGenesisTime({ genesisAt: genesis, simulatedDayOffset: 0 });
  assert.equal(effective0.toISOString(), '2026-01-01T00:00:00.000Z');

  const effective5 = getEffectiveGenesisTime({ genesisAt: genesis, simulatedDayOffset: 5 });
  // Five simulated game days are two real hours at 1 second per game minute.
  assert.equal(effective5.toISOString(), '2025-12-31T22:00:00.000Z');
});

test('getAuthoritativeGameTime derives game day and minute from effective genesis', () => {
  const genesis = '2026-01-01T00:00:00.000Z';
  // 10 days and 30 minutes after genesis
  const nowMs = Date.parse('2026-01-01T04:00:30.000Z');
  
  const time = getAuthoritativeGameTime({
    nowMs,
    genesisAt: genesis,
    simulatedDayOffset: 0,
  });
  assert.equal(time.gameDay, 11);
  assert.equal(time.gameMinute, 30);
  assert.equal(time.effectiveGenesisAt, '2026-01-01T00:00:00.000Z');

  // With a 3-day simulation offset, effective genesis shifts back and game day increases by 3
  const timeWithOffset = getAuthoritativeGameTime({
    nowMs,
    genesisAt: genesis,
    simulatedDayOffset: 3,
  });
  assert.equal(timeWithOffset.gameDay, 14);
  assert.equal(timeWithOffset.gameMinute, 30);
  assert.equal(timeWithOffset.effectiveGenesisAt, '2025-12-31T22:48:00.000Z');
});
