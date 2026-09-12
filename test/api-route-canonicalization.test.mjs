import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { API_ROUTES, routeKey } from '../cloudflare/src/api-registry.ts';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('canonical market and research routes have no runtime aliases', () => {
  const market = read('cloudflare/src/market-api.ts');
  const research = read('cloudflare/src/real-estate-routes.ts');
  const index = read('cloudflare/src/index.ts');
  const technologyApi = read('flutter_client/lib/core/api/earth_api_technology.dart');
  const realEstateApi = read('flutter_client/lib/core/api/earth_api_real_estate.dart');

  assert.doesNotMatch(market, /startsWith\('\/market\/'\)|['"]\/market\/orders['"]|\/cancel\$/);
  assert.doesNotMatch(market, /\/api\/market\/settle/);
  assert.doesNotMatch(research, /corporate-research|corporation\/building-research|corporations\/building-research/);
  assert.doesNotMatch(index, /corporate-research|corporation\/building-research|corporations\/building-research/);
  assert.match(technologyApi, /['"]\/api\/research\/buildings['"]/);
  assert.match(realEstateApi, /['"]\/api\/research\/contribute['"]/);
});

test('canonical cancellation and research operations are registered once', () => {
  const keys = new Set(API_ROUTES.map(routeKey));
  for (const key of [
    'DELETE /api/market/orders/{id}',
    'GET /api/research/buildings',
    'POST /api/research/buildings',
    'POST /api/research/contribute',
  ]) assert.ok(keys.has(key), `missing canonical route ${key}`);
  assert.ok(!keys.has('POST /api/market/orders/{id}/cancel'));
});

test('production routes do not contain fixture identity fallbacks', () => {
  const sources = [
    read('cloudflare/src/index.ts'),
    read('cloudflare/src/auth-routes.ts'),
    read('cloudflare/src/auth-postgres.ts'),
    read('cloudflare/src/house-routes.ts'),
    read('cloudflare/src/institutions-routes.ts'),
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/real-estate-routes.ts'),
    read('cloudflare/src/finance-routes.ts'),
    read('cloudflare/src/net-worth-postgres.ts'),
  ].join('\n');
  assert.doesNotMatch(sources, /H-0044|CITY-0084|TECH-001|amara@earth\.local/);
});

test('House API resolves the authenticated House principal and ignores client heirloom effects', () => {
  const session = read('cloudflare/src/auth-session.ts');
  const routes = read('cloudflare/src/house-routes.ts');
  const house = read('cloudflare/src/house-postgres.ts');
  assert.match(session, /export type ViewerContext/);
  assert.match(session, /accountId: string;[\s\S]*houseId: string;[\s\S]*currentHumanId: string/);
  assert.match(routes, /viewer\.house_id/);
  assert.doesNotMatch(routes, /statBuff/);
  assert.match(house, /SELECT \* FROM houses WHERE id = \$1 LIMIT 1/);
});
