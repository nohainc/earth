import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('Building V2 has no repair or condition authority', () => {
  const source = read('cloudflare/src/building-settlement-v2.ts');
  assert.doesNotMatch(source, /condition|auto_repair|repair_|BUILDING_WEAR|REPAIR_EFFICIENCY|wear/);
  assert.doesNotMatch(source, /UPDATE buildings SET/);
  assert.match(source, /building_physical_upkeep/);
  assert.match(source, /building_output/);
});

test('building condition and repair schema is removed by the forward migration', () => {
  const migration = read('db/migrations/340_remove_building_condition_repair.sql');
  for (const column of ['condition', 'auto_repair_enabled', 'repair_priority', 'wear_points', 'repair_points']) assert.match(migration, new RegExp(`DROP COLUMN IF EXISTS ${column}`));
  assert.match(migration, /DROP TABLE IF EXISTS building_condition_efficiency_curves/);
  assert.match(migration, /technology_effects_effect_type_check/);
});

test('repair API surfaces are gone while construction remains', () => {
  const routes = read('cloudflare/src/real-estate-routes.ts');
  const api = read('flutter_client/lib/core/api/earth_api_real_estate.dart');
  assert.doesNotMatch(routes, /repair|auto-repair/);
  assert.doesNotMatch(api, /repair|auto-repair/);
  assert.match(routes, /complete-construction/);
  assert.match(api, /upgradeBuilding/);
});
