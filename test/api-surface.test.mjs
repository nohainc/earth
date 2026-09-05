import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const indexSource = fs.readFileSync(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');
const houseRoutes = fs.readFileSync(new URL('../cloudflare/src/house-routes.ts', import.meta.url), 'utf8');
const worldApi = fs.readFileSync(new URL('../flutter_client/lib/core/api/earth_api_world.dart', import.meta.url), 'utf8');
const houseApi = fs.readFileSync(new URL('../flutter_client/lib/core/api/earth_api_house.dart', import.meta.url), 'utf8');
const estateApi = fs.readFileSync(new URL('../flutter_client/lib/core/api/earth_api_real_estate.dart', import.meta.url), 'utf8');

test('retired API aliases and client methods stay removed', () => {
  for (const source of [indexSource, houseRoutes, worldApi, houseApi, estateApi]) {
    assert.doesNotMatch(source, /\/api\/world\/recalculate|\/api\/successor|\/api\/dynasty/);
    assert.doesNotMatch(source, /recalculateWorld|dynastyOverview|unlockDynastyPerk|equipDynastyHeirloom|forgeDynastyHeirloom|updateDynastyMotto/);
    assert.doesNotMatch(source, /investInPublicBuilding|acquireBuildingPatentLicense|renewBuildingPatentLicense/);
  }
});

test('canonical replacement routes remain present', () => {
  assert.doesNotMatch(indexSource, /\/api\/day\/advance/);
  assert.match(indexSource, /\/api\/life\/successor/);
  assert.match(houseRoutes, /\/api\/house/);
  assert.match(estateApi, /purchaseBuilding/);
  assert.match(estateApi, /\/api\/real-estate\/purchase/);
});
