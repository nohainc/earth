import test from 'node:test';
import assert from 'node:assert/strict';
import { API_ROUTES, API_ROUTE_OWNERS, API_AUTH_CLASSES, routeKey, validateApiRegistry } from '../cloudflare/src/api-registry.ts';

test('canonical API registry is complete and internally consistent', () => {
  assert.deepEqual(validateApiRegistry(), []);
  assert.ok(API_ROUTES.length >= 30);
  for (const route of API_ROUTES) {
    assert.ok(API_ROUTE_OWNERS.includes(route.owner));
    assert.ok(API_AUTH_CLASSES.includes(route.auth));
    assert.match(route.path, /^(\/api|\/internal)\//);
    assert.match(routeKey(route), /^(GET|POST|PUT|PATCH|DELETE) \/(api|internal)\//);
  }
});

test('registry rejects duplicate routes, missing metadata, and unknown owners', () => {
  const invalid = [{ method: 'GET', path: '/api/test', owner: 'Unknown', auth: undefined, service: '', status: 'ACTIVE' }];
  const failures = validateApiRegistry(invalid);
  assert.ok(failures.some((failure) => failure.includes('unknown owner')));
  assert.ok(failures.some((failure) => failure.includes('unknown auth class')));
  assert.ok(failures.some((failure) => failure.includes('has no service')));
});

test('duplicate METHOD + PATH is rejected even when owners differ', () => {
  const duplicate = [
    { ...API_ROUTES[0] },
    { ...API_ROUTES[0], owner: 'ReadModelRoutes' },
  ];
  assert.match(validateApiRegistry(duplicate).join('\n'), /duplicate route GET \/api\/live/);
});
