import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { API_ROUTES, routeKey } from '../cloudflare/src/api-registry.ts';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('operational audit is internal-only and not exposed as a player API', () => {
  const routes = read('cloudflare/src/read-model-routes.ts');
  const index = read('cloudflare/src/index.ts');
  assert.match(routes, /\/internal\/audit/);
  assert.match(routes, /INTERNAL_ADMIN_TOKEN/);
  assert.doesNotMatch(routes, /\/api\/audit|\/api\/world\/audit/);
  assert.match(index, /url\.pathname\.startsWith\('\/internal\/'\)/);
  assert.ok(API_ROUTES.some((route) => routeKey(route) === 'GET /internal/audit' && route.auth === 'INTERNAL_ADMIN'));
});
