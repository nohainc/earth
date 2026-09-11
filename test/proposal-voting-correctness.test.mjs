import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('proposal creation resolves only the active governance rule', () => {
  const source = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');
  assert.match(source, /FROM governance_rules WHERE institution_id = \$1 AND category = 'governance' AND status = 'active'/);
  assert.doesNotMatch(source, /input\.ruleVersionId/);
  assert.match(source, /expectedGovernanceRuleVersionId/);
});

test('proposal resolution separates human quorum from weighted approval', () => {
  const source = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');
  assert.match(source, /proposal_vote_totals/);
  assert.match(source, /voters: Number\(totals\.voter_count/);
  assert.match(source, /eligibleHumans: Number\(proposal\.eligible_voter_count/);
});

test('governance rules enforce one active version per institution and category', () => {
  const migration = fs.readFileSync('db/migrations/187_proposal_voting_correctness.sql', 'utf8');
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS governance_rules_one_active_category/);
  assert.match(migration, /WHERE status = 'active'/);
});
