import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('client canonical building and Territory surfaces use V3 vocabulary', () => {
  const models = read('flutter_client/lib/models/building_models.dart');
  const realEstate = read('flutter_client/lib/core/api/earth_api_real_estate.dart');
  const navigation = read('flutter_client/lib/core/navigation_registry.dart');
  const dashboard = read('flutter_client/lib/features/command_center/dashboard.dart');
  const institutions = read('flutter_client/lib/core/api/earth_api_institutions.dart');
  assert.match(models, /territoryId/);
  assert.doesNotMatch(models, /cityId|city_id/);
  assert.match(realEstate, /territoryId/);
  assert.doesNotMatch(realEstate, /cityId|city_id/);
  assert.match(navigation, /canonicalRoute: 'territories'/);
  assert.match(navigation, /deprecated transition alias/);
  assert.match(dashboard, /case 'territories'/);
  assert.match(dashboard, /case 'city'/);
  assert.match(institutions, /listCorporationTerritories|getCorporationFiscalState/);
});
