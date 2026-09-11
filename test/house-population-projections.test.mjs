import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/334_house_population_projections.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const read = fs.readFileSync(new URL('../cloudflare/src/read-postgres.ts', import.meta.url), 'utf8');
const world = fs.readFileSync(new URL('../cloudflare/src/world-postgres.ts', import.meta.url), 'utf8');

test('population summaries derive counts from active House affiliations', () => {
  for (const source of [migration, schema]) {
    assert.match(source, /city_population_summary/);
    assert.match(source, /corporation_membership_summary/);
    assert.match(source, /house_affiliations a/);
    assert.match(source, /a\.status = 'ACTIVE'/);
  }
  assert.match(migration, /earth_refresh_population_projections/);
});

test('integrity checks compare cached counters with House-derived summaries', () => {
  assert.match(read, /corporation_membership_summary/);
  assert.match(read, /city_population_summary/);
  assert.match(world, /corporation_membership_summary/);
  assert.match(world, /city_population_summary/);
  assert.doesNotMatch(read, /member_count != \(SELECT COUNT\(\*\) FROM memberships/);
});
