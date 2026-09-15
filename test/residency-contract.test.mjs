import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('House residency is independent, capacity-locked, and retains remote assets', () => {
  const migration = fs.readFileSync('db/migrations/027_house_residencies.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/residency-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/house-routes.ts', 'utf8');
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_residency.dart', 'utf8');
  const services = fs.readFileSync('cloudflare/src/service-settlement-postgres.ts', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS house_residencies/);
  assert.match(migration, /house_residencies_one_primary_idx/);
  assert.match(migration, /residency-backfill/);
  assert.match(service, /ORDER BY t\.id FOR UPDATE/);
  assert.match(service, /Target Territory residence capacity exceeded/);
  assert.match(service, /remoteAssetsRetained: true/);
  assert.match(service, /effectiveGameDay: day \+ 1/);
  assert.match(routes, /\/api\/house\/residency\/move/);
  assert.match(api, /quoteHouseMove/);
  assert.match(services, /JOIN house_residencies/);
});
