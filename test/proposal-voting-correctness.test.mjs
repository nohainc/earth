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

test('V5 amendments enforce one active proposal per authority and policy group', () => {
  const migration = fs.readFileSync('db/migrations/104_v5_governance_policy_group_lock.sql', 'utf8');
  assert.match(migration, /CREATE UNIQUE INDEX v5_governance_one_active_policy_group_idx/);
  assert.match(migration, /WHERE status IN \('VOTING', 'PASSED', 'SCHEDULED'\)/);
});

test('Corporation V4 proposals prefer canonical Constitution governance policy values', () => {
  const source = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');
  assert.match(source, /resolveEffectiveConstitution/);
  assert.match(source, /institutionKind === 'CORPORATION'/);
  assert.match(source, /CORPORATION\.GOVERNANCE\.POLICY_QUORUM_BPS/);
  assert.match(source, /CORPORATION\.GOVERNANCE\.IMPLEMENTATION_DELAY_DAYS/);
  assert.match(source, /constitutionalRuleVersionIds: canonical\?\.versionIds/);
});

test('Earth V4 proposals also resolve canonical Constitution governance policy when available', () => {
  const source = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');
  assert.match(source, /institutionKind === 'CORPORATION' \|\| institutionKind === 'EARTH'/);
});
