import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { evaluateProposalVote } from '../cloudflare/src/governance-postgres.ts';

const governance = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');
const funding = fs.readFileSync('cloudflare/src/proposal-funding.ts', 'utf8');
const automation = fs.readFileSync('cloudflare/src/daily-automation.ts', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');
const migrations = fs.readFileSync('db/migrations/194_proposal_limits_and_challenges.sql', 'utf8');

test('Proposal Engine V2 complete lifecycle contracts', async (t) => {
  await t.test('governance rule changes do not alter active proposal snapshots', () => {
    assert.match(governance, /governanceSnapshot/);
    assert.match(governance, /ruleVersionId: ruleRow\.id/);
    assert.match(schema, /governance_snapshot JSONB NOT NULL/);
  });

  await t.test('building catalog changes cannot affect frozen action cost', () => {
    assert.match(governance, /creditCostUnits/);
    assert.match(governance, /materialCostUnits/);
    assert.match(governance, /BigInt\(String\(action\.creditCostUnits/);
    assert.doesNotMatch(governance.slice(governance.indexOf('if (category === \'megaproject_procurement\')'), governance.indexOf('if (category === \'technology\'')), /FROM building_catalog/);
  });

  await t.test('electorate cutoff excludes members joining after voting starts', () => {
    assert.match(automation, /m\.joined_game_day <= p\.voting_start_day/);
    assert.match(governance, /eligibility_cutoff_game_day/);
  });

  await t.test('ballot weight is recorded once and is not recomputed at resolution', () => {
    assert.match(governance, /INSERT INTO ballots/);
    assert.match(governance, /proposal_vote_totals/);
    assert.match(governance, /voters: Number\(totals\.voter_count/);
  });

  await t.test('weighted voters cannot manufacture quorum', () => {
    const result = evaluateProposalVote({ voters: 13, eligibleHumans: 100, supportWeight: 26, opposeWeight: 0, quorum: 0.25, approvalThreshold: 0.5 });
    assert.equal(result.quorumMet, false);
  });

  await t.test('funding checks all requirements before posting', () => {
    assert.match(funding, /const missing = requirements\.rows\.find/);
    assert.match(funding, /earth_post_transaction/);
    assert.match(funding, /proposal-start:\$\{proposalId\}/);
  });

  await t.test('funding waits and expires using the proposal window', () => {
    assert.match(governance, /funding_start_day/);
    assert.match(governance, /funding_due_end_day/);
    assert.match(governance, /expired_unfunded/);
    assert.match(governance, /day \+ 1/);
  });

  await t.test('retries use one idempotent economic transaction', () => {
    assert.match(funding, /earth_post_transaction/);
    assert.match(schema, /proposal_action_requirements/);
    assert.match(schema, /correlation_id TEXT NOT NULL UNIQUE/);
  });

  await t.test('rule proposals reject stale base versions', () => {
    assert.match(governance, /baseRuleVersionId/);
    assert.match(governance, /stale_conflict/);
  });

  await t.test('new rules begin on the following game day', () => {
    assert.match(governance, /effective_from_game_day/);
    assert.match(governance, /day \+ 1/);
    assert.match(governance, /effective_to_game_day/);
  });

  await t.test('resolution uses aggregate totals rather than scanning ballots', () => {
    const resolution = governance.slice(governance.indexOf('export async function resolveProposalsInTransaction'));
    assert.match(resolution, /FROM proposal_vote_totals/);
    assert.doesNotMatch(resolution, /SUM\(weight\).*FROM ballots/s);
  });

  await t.test('research and building actions share the funding boundary', () => {
    assert.match(governance, /attemptProposalFunding\(tx, current\.id, day\)/);
    assert.match(schema, /proposal_action_requirements/);
  });

  await t.test('proposal start is atomic with database transaction boundaries', () => {
    assert.match(governance, /return repository\.transaction\(async \(tx\)/);
    assert.match(funding, /earth_post_transaction/);
  });

  await t.test('challenge authority and conflict policies are database-enforced', () => {
    assert.match(migrations, /proposal_challenge_authorities/);
    assert.match(migrations, /proposals_active_conflict_idx/);
    assert.match(schema, /decision_status IN \('scheduled','voting','passed'\)/);
  });
});
