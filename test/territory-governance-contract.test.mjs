import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Territory capacity is physical and Corporation context is explicit', () => {
  const migration = fs.readFileSync('db/migrations/023_territory_governance_relation.sql', 'utf8');
  const source = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS territory_governance/);
  assert.match(migration, /governing_institution_id TEXT NOT NULL REFERENCES institutions/);
  assert.match(migration, /effective_from_game_day BIGINT/);
  assert.match(migration, /INSERT INTO territory_governance/);
  assert.match(source, /corporation_id/);
  assert.match(source, /corporation_name/);
  assert.doesNotMatch(source, /territory_governance/);
  assert.match(source, /infrastructure: infrastructure\.rows/);
  assert.match(source, /services: capacity\?\.service_capacity/);
});
