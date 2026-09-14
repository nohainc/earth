import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const migration = read('db/migrations/004_public_infrastructure_credit.sql');
const territory = read('cloudflare/src/territory-capacity-postgres.ts');

test('public catalog definitions are CREDIT-only service/capacity definitions', () => {
  assert.match(migration, /building_catalog_public_credit_only_ck/);
  assert.match(migration, /resource_input_units = '\{\}'::jsonb/);
  assert.match(migration, /resource_output_units = '\{\}'::jsonb/);
  assert.match(migration, /earth_validate_public_catalog_effect/);
  assert.match(migration, /PUBLIC_SLOTS/);
  assert.doesNotMatch(migration, /resource_input_units[^\n]*MATERIAL|resource_output_units[^\n]*ENERGY/);
});

test('public Territory building construction is Corporation CREDIT-funded', () => {
  assert.match(territory, /isPublic \? 'TREASURY' : 'WALLET'/);
  assert.match(territory, /a\.asset_id = 1/);
  assert.match(territory, /isPublic \? 'CORPORATION' : 'HOUSE'/);
  assert.doesNotMatch(territory, /resource_input_units|resource_output_units/);
});
