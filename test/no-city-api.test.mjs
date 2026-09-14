import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('City lifecycle APIs are removed after the V3 clean break', () => {
  const routes = read('cloudflare/src/institutions-routes.ts');
  const registry = read('cloudflare/src/api-registry.ts');
  const service = read('cloudflare/src/institutions-postgres.ts');
  for (const source of [routes, registry, service]) {
    assert.doesNotMatch(source, /createCity|listCities|cityQualification|\/api\/cities|city_id|capital_city/);
  }
});
