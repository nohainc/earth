import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Territory rights remain historical schema but are retired from V5 runtime', () => {
  const migration = fs.readFileSync('db/migrations/051_territory_rights_and_leases.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/territory-rights-postgres.ts', 'utf8');
  const construction = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/real-estate-routes.ts', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS territory_rights/);
  assert.match(migration, /effective_from_game_day/);
  assert.match(migration, /effective_to_game_day/);
  assert.match(migration, /territory_lease_payments/);
  assert.match(migration, /territory_right_events/);
  assert.match(migration, /ALTER TABLE construction_projects/);
  assert.match(construction, /territory_right_id/);
  assert.match(routes, /Territory use-rights are retired in V5/);
  assert.match(routes, /status: 410/);
});

test('Historical Territory right service remains isolated from the runtime scheduler', () => {
  const service = fs.readFileSync('cloudflare/src/territory-rights-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  assert.match(service, /territory_rights/);
  assert.doesNotMatch(scheduler, /settleTerritoryLeases/);
});
