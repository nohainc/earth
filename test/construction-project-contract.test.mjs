import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('construction uses durable projects and only completion commissions production assets', () => {
  const migration = fs.readFileSync('db/migrations/022_construction_project_lifecycle.sql', 'utf8');
  const command = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
  const completion = fs.readFileSync('cloudflare/src/construction-settlement-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/real-estate-routes.ts', 'utf8');
  assert.match(migration, /construction_projects/);
  assert.match(migration, /UNDER_CONSTRUCTION/);
  assert.match(command, /'UNDER_CONSTRUCTION'/);
  assert.match(command, /expectedCompletionGameDay/);
  assert.match(completion, /status = 'COMPLETED'/);
  assert.match(completion, /commissioned_game_day/);
  assert.match(scheduler, /completeDueConstructionProjects/);
  assert.match(routes, /real-estate\/projects/);
});
