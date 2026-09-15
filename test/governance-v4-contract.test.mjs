import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('V4 governance uses typed actions, immutable snapshots, House ballots, and capability checks', () => {
  const migration = fs.readFileSync('db/migrations/029_governance_v4.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/governance-v4-postgres.ts', 'utf8');
  assert.match(migration, /governance_proposals_v4/);
  assert.match(migration, /action_type TEXT NOT NULL CHECK/);
  assert.match(migration, /action_snapshot JSONB NOT NULL/);
  assert.match(migration, /rule_snapshot JSONB NOT NULL/);
  assert.match(migration, /governance_ballots_v4/);
  assert.match(migration, /PRIMARY KEY \(proposal_id, house_id\)/);
  assert.match(service, /const ACTIONS = new Set/);
  assert.match(service, /Unregistered governance action/);
  assert.match(service, /organization_capabilities/);
  assert.match(service, /ON CONFLICT \(proposal_id, house_id\) DO UPDATE/);
  assert.match(service, /resolveGovernanceProposalV4/);
});
