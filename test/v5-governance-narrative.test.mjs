import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('V5 governance proposals persist narrative fields and backfill historical events', () => {
  const migration = read('db/migrations/142_v5_governance_proposal_narrative.sql');
  assert.match(migration, /ADD COLUMN title TEXT/);
  assert.match(migration, /ADD COLUMN body TEXT/);
  assert.match(migration, /V5_POLICY_PROPOSAL_CREATED/);
  assert.match(migration, /proposalId /);
  assert.match(migration, /ALTER COLUMN title SET NOT NULL/);

  const service = read('cloudflare/src/v5-governance-postgres.ts');
  assert.match(service, /p\.title, p\.body/);
  assert.match(service, /INSERT INTO v5_governance_proposals \(id, subject_type, subject_id, action_type, payload, title, body/);
  assert.match(service, /input\.title\.trim\(\)/);
  assert.match(service, /input\.body\?\.trim\(\) \|\| null/);
});

test('V5 governance UI uses persisted proposal titles instead of action types', () => {
  const panel = read('flutter_client/lib/features/governance/governance_panels.dart');
  assert.match(panel, /proposal\['title'\]/);
  assert.doesNotMatch(panel, /proposal\['action_type'\][\s\S]{0,80}V5 governance proposal/);
});
