import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Territory rights are explicit, time-bounded, capacity-scoped, and auditable', () => {
  const migration = fs.readFileSync('db/migrations/051_territory_rights_and_leases.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/territory-rights-postgres.ts', 'utf8');
  const construction = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/real-estate-routes.ts', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS territory_rights/);
  assert.match(migration, /effective_from_game_day/);
  assert.match(migration, /effective_to_game_day/);
  assert.match(migration, /territory_lease_payments/);
  assert.match(migration, /territory_right_events/);
  assert.match(migration, /ALTER TABLE construction_projects/);
  assert.match(service, /FOR UPDATE/);
  assert.match(service, /Territory private right capacity exceeded/);
  assert.match(service, /earth_post_transaction/);
  assert.match(service, /Insufficient CREDIT/);
  assert.match(construction, /active private Territory use right/);
  assert.match(construction, /territory_right_id/);
  assert.match(scheduler, /settleTerritoryLeases/);
  assert.match(routes, /territoryRightsMatch/);
  assert.match(routes, /real-estate\/rights/);
});

test('Territory rights cannot be acquired as public infrastructure by a House', () => {
  const service = fs.readFileSync('cloudflare/src/territory-rights-postgres.ts', 'utf8');
  assert.match(service, /Only private House rights are currently available/);
  assert.match(service, /holder_type = 'HOUSE'/);
});
