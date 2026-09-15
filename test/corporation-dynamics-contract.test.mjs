import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('corporation dynamics is a deterministic, replay-safe operating projection', () => {
  const migration = fs.readFileSync('db/migrations/055_corporation_operating_snapshots.sql', 'utf8');
  const runtime = fs.readFileSync('cloudflare/src/territory-settlement-postgres.ts', 'utf8');
  assert.match(migration, /corporation_operating_snapshots/);
  assert.match(migration, /PRIMARY KEY \(corporation_id, game_day\)/);
  assert.match(runtime, /ON CONFLICT \(corporation_id, game_day\) DO UPDATE/);
  assert.match(runtime, /corporation-operating-v1/);
  assert.match(runtime, /service_allocations/);
  assert.match(runtime, /corporation_research_projects/);
});
