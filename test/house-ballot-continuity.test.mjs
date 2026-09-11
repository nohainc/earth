import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('proposal ballots are unique per House while preserving casting Human audit', () => {
  const migration = read('db/migrations/304_house_unique_proposal_ballots.sql');
  const governance = read('cloudflare/src/governance-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /ADD COLUMN IF NOT EXISTS house_id/);
  assert.match(migration, /PRIMARY KEY \(proposal_id, house_id\)/);
  assert.match(migration, /human_id remains the historical Human/);
  assert.match(governance, /INSERT INTO ballots \(proposal_id, house_id, human_id, choice, weight\)/);
  assert.match(governance, /ON CONFLICT \(proposal_id, house_id\) DO NOTHING/);
  assert.match(schema, /house_id TEXT NOT NULL REFERENCES houses\(id\)/);
  assert.match(schema, /PRIMARY KEY \(proposal_id, house_id\)/);
});
