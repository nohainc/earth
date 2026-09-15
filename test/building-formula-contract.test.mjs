import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('building catalog exposes canonical family and formula versions', () => {
  const migration = fs.readFileSync('db/migrations/021_building_family_formula_metadata.sql', 'utf8');
  const formula = fs.readFileSync('cloudflare/src/building-formulas.ts', 'utf8');
  const catalog = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
  assert.match(migration, /family_code/);
  assert.match(migration, /tier_formula_version/);
  assert.match(formula, /BUILDING_TIER_MULTIPLIERS_BPS/);
  assert.match(formula, /building-formula-v1/);
  assert.match(catalog, /family_code/);
  assert.match(catalog, /tier_formula_version/);
});
