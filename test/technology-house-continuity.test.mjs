import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('Technology and IP remain corporation-owned across Human succession', () => {
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const building = read('cloudflare/src/building-settlement-v2.ts');
  const technology = read('cloudflare/src/technology-postgres.ts');
  const corporationResearch = read('cloudflare/src/corporation-building-research-postgres.ts');

  assert.match(lifecycle, /INSERT INTO memberships \(human_id, corporation_id, city_id, joined_game_day\)/);
  assert.match(building, /earth_building_corporation_economic_id\(b\.id\)/);
  assert.match(technology, /corporationEconomicId/);
  assert.match(corporationResearch, /corporation_research_projects/);
  assert.doesNotMatch(lifecycle, /DELETE FROM technology|DELETE FROM .*patent|UPDATE .*license.*status/);
});
