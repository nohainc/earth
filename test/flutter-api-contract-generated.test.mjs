import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const contract = JSON.parse(fs.readFileSync(path.join(root, 'generated', 'api-contract.json'), 'utf8'));
const apiRoot = path.join(root, 'flutter_client', 'lib', 'core', 'api');

function flutterApiSource() {
  return fs.readdirSync(apiRoot)
    .filter((file) => file.startsWith('earth_api') && file.endsWith('.dart'))
    .map((file) => fs.readFileSync(path.join(apiRoot, file), 'utf8'))
    .join('\n');
}

function normalize(pathValue) {
  let value = pathValue.split('?')[0];
  if (value.includes('$') && !value.includes('/$')) value = value.split('$')[0];
  value = value.replace(/\$\{?\w+\}?/g, '{id}');
  return value.replace(/\/$/, '') || '/';
}

function matches(pattern, actual) {
  const expectedParts = pattern.split('/');
  const actualParts = actual.split('/');
  return expectedParts.length === actualParts.length && expectedParts.every((part, index) =>
    /^\{[^}]+\}$/.test(part) || part === actualParts[index]);
}

function extractedClientRoutes(source) {
  const routes = [];
  const requestPattern = /_request\(\s*(['"])([^'"\n]+)\1(?:\s*,\s*method:\s*['"](GET|POST|PUT|PATCH|DELETE)['"])?/g;
  for (const match of source.matchAll(requestPattern)) {
    const route = normalize(match[2]);
    if (route.startsWith('/api/')) routes.push({ method: match[3] ?? 'GET', path: route });
  }
  return [...new Map(routes.map((route) => [`${route.method} ${route.path}`, route])).values()];
}

test('generated API contract is synchronized with the server registry', () => {
  assert.equal(contract.version, 1);
  assert.ok(Array.isArray(contract.routes) && contract.routes.length > 0);
  const source = flutterApiSource();
  const clientRoutes = extractedClientRoutes(source);
  const activeRoutes = contract.routes.filter((route) => route.status === 'ACTIVE');
  const missing = clientRoutes.filter((client) => !activeRoutes.some((server) =>
    server.method === client.method && matches(server.path, client.path)));
  assert.deepEqual(missing, [], 'Flutter calls an unknown method/path in the server contract');

  for (const retired of ['/edge/events', '/api/player/daily-briefing']) {
    assert.doesNotMatch(source, new RegExp(retired.replaceAll('/', '\\/')));
  }
});

test('generated contract preserves route ownership and authorization metadata', () => {
  for (const route of contract.routes) {
    assert.ok(contract.owners.includes(route.owner), `${route.path} has an unknown owner`);
    assert.ok(contract.authClasses.includes(route.auth), `${route.path} has an unknown auth class`);
    assert.ok(route.service && route.status, `${route.method} ${route.path} is incomplete`);
  }
});
