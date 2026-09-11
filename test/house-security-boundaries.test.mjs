import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('session resolution is account/House based and only returns the current active Human', () => {
  const source = read('cloudflare/src/auth-session.ts');
  assert.match(source, /JOIN auth_accounts a ON a\.id = s\.account_id/);
  assert.match(source, /JOIN humans ON humans\.id = houses\.current_human_id/);
  assert.match(source, /humans\.account_status = 'active'/);
  assert.match(source, /humans\.life_status = 'active'/);
});

test('telemetry cannot be widened into an admin or cross-House read by URL parameters', () => {
  const source = read('cloudflare/src/index.ts');
  assert.match(source, /const humanId = viewer\.id;/);
  assert.doesNotMatch(source, /url\.searchParams\.get\('all'\).*humanId/);
});

test('institution authorization requires explicit active governance roles', () => {
  const source = read('cloudflare/src/institutions-postgres.ts');
  assert.match(source, /institution_governance_roles/);
  assert.match(source, /status = 'ACTIVE'/);
  assert.match(source, /role_code = ANY/);
});

test('feature-disabled mutations are enforced at the server boundary', () => {
  const source = read('cloudflare/src/index.ts');
  assert.match(source, /featureEnabled\(env, 'spotMarket'\)/);
  assert.match(source, /featureEnabled\(env, 'mortality'\)/);
});
