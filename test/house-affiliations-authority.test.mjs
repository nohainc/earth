import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/333_house_affiliations_authority.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const lifecycle = fs.readFileSync(new URL('../cloudflare/src/lifecycle-postgres.ts', import.meta.url), 'utf8');
const institutions = fs.readFileSync(new URL('../cloudflare/src/institutions-postgres.ts', import.meta.url), 'utf8');

test('House affiliations are authoritative and legacy memberships are one-way compatibility', () => {
  assert.match(migration, /DROP TRIGGER IF EXISTS memberships_house_affiliation_trigger/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_set_house_affiliation/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_project_house_affiliation_to_memberships/);
  assert.match(migration, /CREATE OR REPLACE VIEW house_membership_compatibility/);
  assert.doesNotMatch(migration, /CREATE TRIGGER memberships_house_affiliation_trigger/);
  assert.match(schema, /CREATE OR REPLACE VIEW house_membership_compatibility/);
  assert.match(lifecycle, /earth_project_house_affiliation_to_memberships/);
  assert.match(institutions, /earth_set_house_affiliation/);
});

test('succession does not delete the persistent House affiliation', () => {
  const successionSection = lifecycle.slice(lifecycle.indexOf('export async function processHouseMortality'));
  assert.doesNotMatch(successionSection, /DELETE FROM memberships WHERE human_id = \$1/);
  assert.match(successionSection, /compatibility membership projection/);
});
