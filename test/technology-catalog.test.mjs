import test from 'node:test';
import assert from 'node:assert/strict';
import { TECHNOLOGY_CATALOG, TECHNOLOGY_CATALOG_DETAILS } from '../cloudflare/src/technology-postgres.ts';

test('technology catalog remains bounded and engine-controlled', () => {
  assert.deepEqual([...TECHNOLOGY_CATALOG], [
    'Automated Assembly',
    'Clean Energy Systems',
    'Food Synthesis',
    'Predictive Maintenance',
    'Civic Network Infrastructure',
  ]);
  assert.equal(TECHNOLOGY_CATALOG_DETAILS.length, TECHNOLOGY_CATALOG.length);
  for (const technology of TECHNOLOGY_CATALOG_DETAILS) {
    assert.equal(technology.kind, 'approved_capability');
    assert.equal(technology.tradeable, false);
    assert.equal(technology.playerCreated, false);
    assert.ok(technology.researchCost >= 240);
    assert.ok(Array.isArray(technology.prerequisites));
  }
});
