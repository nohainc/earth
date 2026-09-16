import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('corporation founding refreshes capacity from the building catalog footprint', () => {
  const migration = fs.readFileSync('db/migrations/079_fix_territory_capacity_building_footprint.sql', 'utf8');
  assert.match(migration, /JOIN building_catalog bc ON bc\.id = b\.catalog_id/);
  assert.match(migration, /SUM\(bc\.slot_footprint\)/g);
  assert.doesNotMatch(migration, /SUM\(b\.slot_footprint\)/);
});
