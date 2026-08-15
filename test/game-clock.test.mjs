import test from 'node:test';
import assert from 'node:assert/strict';
import { projectGameDeadline } from '../cloudflare/src/game-clock.ts';

test('projects a governance deadline into game and real time', () => {
  const deadline = projectGameDeadline({
    gameDay: 100,
    gameMinute: 120,
    closesAt: '2026-08-15T00:01:40.000Z',
    nowMs: Date.parse('2026-08-15T00:00:00.000Z'),
  });
  assert.deepEqual(deadline, {
    gameDay: 100,
    gameMinute: 220,
    realSecondsRemaining: 100,
    closesAt: '2026-08-15T00:01:40.000Z',
  });
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
