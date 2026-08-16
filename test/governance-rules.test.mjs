import test from 'node:test';
import assert from 'node:assert/strict';
import { politicalMaturityReached } from '../cloudflare/src/governance-postgres.ts';

test('political maturity is locked until the eligibility game day', () => {
  assert.equal(politicalMaturityReached(184, 214), false);
  assert.equal(politicalMaturityReached(213, 214), false);
  assert.equal(politicalMaturityReached(214, 214), true);
  assert.equal(politicalMaturityReached(215, 214), true);
});
