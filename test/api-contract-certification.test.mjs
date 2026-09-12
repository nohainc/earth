import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { API_ROUTES, validateApiRegistry } from '../cloudflare/src/api-registry.ts';

const retiredPaths = [
  '/api/human/successor/settle',
  '/api/technology/adopt',
  '/api/technology/share',
  '/api/technology/transfer',
  '/api/researches/building',
  '/api/businesses/B-1048/policy',
];

test('all registered routes have unique ownership and protected mutations', () => {
  assert.deepEqual(validateApiRegistry(), []);
  for (const route of API_ROUTES) {
    const publicBootstrap = route.owner === 'AuthRoutes' &&
      ['/api/auth/register', '/api/auth/login'].includes(route.path);
    if (route.method !== 'GET' && !publicBootstrap) {
      assert.notEqual(route.auth, 'PUBLIC', `${route.method} ${route.path}`);
    }
  }
  const governanceWrites = API_ROUTES.filter((route) => route.path.startsWith('/api/governance/') && route.method !== 'GET');
  assert.ok(governanceWrites.length > 0);
  assert.ok(governanceWrites.every((route) => route.auth === 'HUMAN_SELF' || route.auth === 'INSTITUTION_ROLE'));
});

test('retired API paths are absent from the live server surface', async () => {
  const port = 8994;
  const server = spawn('node', ['server.js'], {
    env: { ...process.env, PORT: String(port), NODE_ENV: 'test', DATABASE_URL: '' },
    stdio: 'ignore',
  });
  try {
    for (let attempt = 0; attempt < 40; attempt += 1) {
      try {
        if ((await fetch(`http://127.0.0.1:${port}/api/health`)).ok) break;
      } catch {}
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    for (const path of retiredPaths) {
      const response = await fetch(`http://127.0.0.1:${port}${path}`);
      assert.equal(response.status, 404, path);
      const body = await response.json();
      assert.equal(body.ok, false);
    }
  } finally {
    server.kill('SIGKILL');
  }
});
