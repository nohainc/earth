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

test('clean baseline contains no building condition or repair schema', () => {
  const schema = read('db/baseline/01_schema.sql').toLowerCase();
  const catalog = read('db/baseline/03_reference_data.sql').toLowerCase();
  const source = `${schema}\n${catalog}`;
  for (const removed of ['condition', 'durability', 'damage', 'wear', 'repair', 'auto_repair']) {
    assert.doesNotMatch(source, new RegExp(removed), `baseline must not contain ${removed}`);
  }
});

test('repair API surfaces are gone while construction remains', () => {
  const routes = read('cloudflare/src/real-estate-routes.ts');
  const api = read('flutter_client/lib/core/api/earth_api_real_estate.dart');
  assert.doesNotMatch(routes, /repair|auto-repair/);
  assert.doesNotMatch(api, /repair|auto-repair/);
  assert.match(routes, /complete-construction/);
  assert.match(api, /upgradeBuilding/);
});
