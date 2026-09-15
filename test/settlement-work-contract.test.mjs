import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('resumable settlement work has database-backed lease and retry contracts', () => {
  const migration = read('db/migrations/015_resumable_settlement_work.sql');
  const worker = read('cloudflare/src/settlement-work-postgres.ts');
  assert.match(migration, /FOR UPDATE SKIP LOCKED/);
  assert.match(migration, /earth_claim_settlement_day/);
  assert.match(migration, /earth_heartbeat_settlement_day/);
  assert.match(migration, /earth_complete_settlement_day/);
  assert.match(migration, /earth_fail_settlement_day/);
  assert.match(migration, /UNIQUE \(game_day, phase_id, shard\)/);
  assert.match(worker, /lease_expires_at/);
  assert.match(worker, /attempt_count/);
  assert.match(worker, /Settlement work lease lost/);
});
