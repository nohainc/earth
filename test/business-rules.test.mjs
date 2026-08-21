import test from 'node:test';
import assert from 'node:assert/strict';
import { businessSectorAccess } from '../cloudflare/src/business-rules.ts';

test('independent characters can start the starter business sectors', () => {
  for (const sector of ['maintenance', 'machines', 'components']) {
    assert.equal(businessSectorAccess(sector, false, false).allowed, true);
  }
});

test('city affiliation unlocks industrial sectors but not specialized services', () => {
  assert.equal(businessSectorAccess('energy', true, false).allowed, true);
  assert.equal(businessSectorAccess('consulting', true, false).allowed, false);
});

test('corporation membership unlocks specialized service sectors', () => {
  assert.equal(businessSectorAccess('healthcare', true, true).allowed, true);
  assert.equal(businessSectorAccess('education', false, true).allowed, false);
});
