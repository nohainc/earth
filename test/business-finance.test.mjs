import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyBusinessFinancialStatus } from '../cloudflare/src/business-finance.ts';

const state = (overrides = {}) => classifyBusinessFinancialStatus({
  profit: 10,
  condition: 80,
  currentStatus: 'active',
  sinceGameDay: null,
  gameDay: 100,
  ...overrides,
});

test('business financial status uses profit and condition, not condition alone', () => {
  assert.equal(state(), 'active');
  assert.equal(state({ profit: -1 }), 'distressed');
  assert.equal(state({ condition: 0 }), 'distressed');
});

test('business insolvency becomes eligible after seven game days and preserves bankruptcy', () => {
  assert.equal(state({ profit: -1, sinceGameDay: 93 }), 'insolvent');
  assert.equal(state({ profit: -1, sinceGameDay: 93, currentStatus: 'bankrupt' }), 'bankrupt');
});
