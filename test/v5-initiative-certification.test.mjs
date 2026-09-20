import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { calculateMatching } from '../cloudflare/src/public-projects.ts';

const governance = fs.readFileSync('cloudflare/src/v5-governance-postgres.ts', 'utf8');
const action = fs.readFileSync('cloudflare/src/v5-governance.ts', 'utf8');
const materializer = fs.readFileSync('cloudflare/src/v5-initiatives-postgres.ts', 'utf8');
const initiatives = fs.readFileSync('cloudflare/src/initiatives-postgres.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
const commitments = fs.readFileSync('db/migrations/158_automatic_initiative_funding_commitments.sql', 'utf8');
const scope = fs.readFileSync('db/migrations/151_v5_initiative_governance.sql', 'utf8');

test('V5 Governance activation is the only Initiative creation boundary', () => {
  assert.match(governance, /v5_governance_activation_queue/);
  assert.match(governance, /row\.action_type === 'INITIATIVE_CREATE'/);
  assert.match(governance, /materializeV5Initiative\(tx/);
  assert.match(materializer, /ON CONFLICT \(governance_proposal_id\) DO NOTHING/);
  assert.doesNotMatch(routes, /INSERT INTO v5_initiatives/);
});

test('Voting proposals cannot materialize Initiatives', () => {
  assert.match(governance, /status IN \('VOTING','PASSED','SCHEDULED'\)/);
  assert.match(governance, /v5_governance_activation_queue/);
  assert.match(materializer, /governance_proposal_id/);
  assert.match(scope, /governance_proposal_id TEXT NOT NULL UNIQUE REFERENCES v5_governance_proposals/);
});

test('Authorized Initiative parameters are frozen in the V5 action snapshot', () => {
  assert.match(governance, /proposalInputPayload/);
  assert.match(governance, /JSON\.stringify\(proposalPayload\)/);
  assert.match(materializer, /input\.action\.fundingTargetUnits/);
  assert.match(materializer, /input\.action\.matchingCapUnits/);
  assert.match(materializer, /input\.action\.outcome/);
  assert.match(materializer, /governance_proposal_id/);
});

test('CREDIT scaling and House contribution/refund paths remain exact and double-entry', () => {
  const parseCredit = (value) => { const [whole, fraction = ''] = String(value).split('.'); return BigInt(whole) * 100n + BigInt((fraction + '00').slice(0, 2)); };
  assert.equal(parseCredit('500.00'), 50000n);
  assert.equal(parseCredit('0.01'), 1n);
  assert.match(routes, /parseCreditAmount\(parsed\.value\.amountCredit/);
  assert.match(initiatives, /owner_type = 'HOUSE'/);
  assert.match(initiatives, /INITIATIVE_CONTRIBUTION/);
  assert.match(initiatives, /INITIATIVE_REFUND/);
  assert.match(initiatives, /postEconomicTransaction/);
  assert.match(initiatives, /postSettlementTransaction/);
});

test('Treasury and matching commitments are bounded and consumed automatically', () => {
  assert.match(commitments, /commitment_type.*TREASURY.*MATCHING/s);
  assert.match(initiatives, /treasuryAuthorized/);
  assert.match(initiatives, /matchingToConsume/);
  assert.match(initiatives, /INITIATIVE_TREASURY_FUNDING/);
  assert.match(initiatives, /INITIATIVE_MATCHING_FUNDING/);
  assert.match(initiatives, /status = 'RELEASED'/);
  assert.doesNotMatch(routes, /Manual matching-pool funding is accepted/);
  assert.match(routes, /Manual matching-pool funding is retired/);
});

test('Breadth matching is stable at the 99/100/101 supporter boundary', () => {
  const options = (supporterCount) => ({ contributionUnits: 1000n, supporterCount: BigInt(supporterCount), poolRemaining: 1000000n, targetRemaining: 1000000n, matchBps: 10000n, policy: 'BREADTH_MATCH', breadthBonusBpsPerSupporter: 25n, breadthSupporterCap: 100n });
  const at99 = calculateMatching(options(99));
  const at100 = calculateMatching(options(100));
  const at101 = calculateMatching(options(101));
  assert.ok(at99 < at100);
  assert.equal(at100, at101);
  assert.equal(calculateMatching({ ...options(101), policy: 'NONE' }), 0n);
});

test('Earth and Corporation scope are the only Initiative authorities', () => {
  assert.match(scope, /scope_type TEXT NOT NULL CHECK \(scope_type IN \('EARTH','CORPORATION'\)\)/);
  assert.match(governance, /subjectType === 'CORPORATION'/);
  assert.match(governance, /house_affiliations/);
  assert.match(action, /beneficiary and recipient authority fields are not allowed/);
  assert.doesNotMatch(action, /TERRITORY.*beneficiary/);
});

test('Settlement is automatic, replay-safe, and idempotent', () => {
  assert.match(initiatives, /settleDueInitiativesInTransaction/);
  assert.match(initiatives, /FOR UPDATE SKIP LOCKED/);
  assert.match(initiatives, /correlationId: `initiative-refund:/);
  assert.match(initiatives, /correlationId: `initiative-funding:/);
  assert.match(initiatives, /correlationId: input\.correlationId/);
  assert.match(initiatives, /alreadyProcessed: true/);
  assert.match(initiatives, /postSettlementTransaction/);
  assert.match(materializer, /ON CONFLICT \(initiative_id\) DO NOTHING/);
  assert.match(materializer, /initiative-activation:/);
});

test('Ordinary Humans cannot route Earth treasury money', () => {
  assert.match(routes, /Manual Earth treasury funding is retired/);
  assert.match(routes, /status: 410/);
  assert.doesNotMatch(initiatives, /input\.humanId.*TREASURY/);
  assert.match(materializer, /treasuryAuthorizedUnits/);
  assert.match(commitments, /governance_proposal_id/);
});
