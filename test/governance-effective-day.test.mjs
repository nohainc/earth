import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveV5GovernanceTiming } from '../cloudflare/src/v5-governance.ts';

test('Governance derives the earliest effective day after voting and delay', () => {
  const timing = deriveV5GovernanceTiming(100, 7, 2);
  assert.deepEqual(timing, {
    votingStartGameDay: 101,
    votingEndGameDay: 108,
    implementationDelayDays: 2,
    earliestValidEffectiveGameDay: 111,
  });
});
