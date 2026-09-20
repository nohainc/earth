import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const scopeMigration = fs.readFileSync('db/migrations/151_v5_initiative_governance.sql', 'utf8');
const action = fs.readFileSync('cloudflare/src/v5-governance.ts', 'utf8');
const proposalActions = fs.readFileSync('cloudflare/src/proposal-actions.ts', 'utf8');
const proposalService = fs.readFileSync('cloudflare/src/v5-governance-postgres.ts', 'utf8');
const materializer = fs.readFileSync('cloudflare/src/v5-initiatives-postgres.ts', 'utf8');
const lifecycleMigration = fs.readFileSync('db/migrations/153_v5_initiative_financial_lifecycle.sql', 'utf8');
const executionMigration = fs.readFileSync('db/migrations/156_initiative_execution_requirements.sql', 'utf8');
const legacyMigration = fs.readFileSync('db/migrations/154_migrate_legacy_initiatives.sql', 'utf8');
const legacyPrograms = fs.readFileSync('cloudflare/src/global-programs-postgres.ts', 'utf8');
const legacyProjects = fs.readFileSync('cloudflare/src/public-projects-postgres.ts', 'utf8');
const outcomes = fs.readFileSync('cloudflare/src/initiative-outcomes.ts', 'utf8');
const outcomeMigration = fs.readFileSync('db/migrations/157_typed_initiative_outcomes.sql', 'utf8');
const fundingMigration = fs.readFileSync('db/migrations/158_automatic_initiative_funding_commitments.sql', 'utf8');

test('INITIATIVE_CREATE is a canonical V5 action with a complete materialization table', () => {
  assert.match(action, /\| 'INITIATIVE_CREATE'/);
  assert.match(proposalActions, /actionType: 'INITIATIVE_CREATE'/);
  assert.match(scopeMigration, /CREATE TABLE IF NOT EXISTS v5_initiatives/);
  assert.match(scopeMigration, /governance_proposal_id TEXT NOT NULL UNIQUE REFERENCES v5_governance_proposals\(id\)/);
  assert.match(scopeMigration, /scope_type TEXT NOT NULL CHECK \(scope_type IN \('EARTH','CORPORATION'\)\)/);
  assert.match(scopeMigration, /outcome JSONB NOT NULL/);
  assert.match(scopeMigration, /physical_target JSONB/);
});

test('initiative definitions are normalized into the frozen proposal snapshot', () => {
  assert.match(proposalService, /input\.actionType === 'INITIATIVE_CREATE'/);
  assert.match(proposalService, /fundingTargetCredit/);
  assert.match(proposalService, /parseCreditAmount/);
  assert.match(proposalService, /delete initiativePayload\.description/);
  assert.match(proposalService, /validateProposalActionSnapshot\(action as unknown as Record<string, unknown>\)/);
  assert.match(proposalService, /JSON\.stringify\(proposalPayload\)/);
});

test('only scheduled V5 activation can materialize an initiative', () => {
  assert.match(proposalService, /row\.action_type === 'INITIATIVE_CREATE'/);
  assert.match(proposalService, /materializeV5Initiative\(tx/);
  assert.match(materializer, /governance_proposal_id = \$1/);
  assert.match(materializer, /ON CONFLICT \(governance_proposal_id\) DO NOTHING/);
  assert.match(materializer, /V5_INITIATIVE_ACTIVATED/);
  assert.match(materializer, /physical_target/);
  assert.doesNotMatch(legacyPrograms, /governance_proposals_v4/);
  assert.doesNotMatch(legacyProjects, /governance_proposals_v4/);
});

test('initiative authority is never represented by Organization or Territory beneficiary fields', () => {
  assert.match(action, /Physical placement\/capacity metadata/);
  assert.match(action, /beneficiary and recipient authority fields are not allowed/);
  assert.match(proposalActions, /Initiative authority must be Earth or Corporation scope/);
  assert.match(fs.readFileSync('db/migrations/152_v5_initiative_scope_normalization.sql', 'utf8'), /Governance authority only: EARTH or CORPORATION/);
});

test('Corporation initiatives use the standard V5 membership and frozen electorate checks', () => {
  assert.match(proposalService, /async function canPropose[\s\S]*?house_affiliations[\s\S]*?status = 'ACTIVE'/);
  assert.match(proposalService, /SELECT 1 FROM v5_governance_electorate_snapshots_v5/);
  assert.match(proposalService, /if \(input\.subjectType === 'CORPORATION'\) initiativePayload\.corporationId = input\.subjectId/);
  assert.match(proposalService, /Corporation initiative must target the proposal Corporation/);
});

test('Programs and Public Projects share the canonical Initiative financial lifecycle', () => {
  for (const table of ['initiative_contributions', 'initiative_funding_commitments', 'initiative_executions', 'initiative_outcomes']) {
    assert.match(lifecycleMigration, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`));
  }
  assert.match(materializer, /initiative_funding_commitments/);
  assert.match(materializer, /initiative_executions/);
  assert.match(materializer, /initiative_outcomes/);
  assert.match(legacyMigration, /MIGRATED-INIT-PROGRAM/);
  assert.match(legacyMigration, /MIGRATED-INIT-PROJECT/);
  assert.match(legacyMigration, /initiative_contributions/);
  assert.match(fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8'), /settleDueInitiativesInTransaction/);
});

test('funding and execution are separate, explicit lifecycle concerns', () => {
  assert.match(executionMigration, /required_duration_game_days/);
  assert.match(executionMigration, /required_resource_requirements/);
  assert.match(executionMigration, /progress_model/);
  assert.match(materializer, /progressModel/);
  assert.match(materializer, /executionDurationGameDays/);
  assert.match(fs.readFileSync('cloudflare/src/initiatives-postgres.ts', 'utf8'), /advanceInitiativeExecutionsInTransaction/);
  assert.match(fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8'), /execution: await advanceInitiativeExecutionsInTransaction/);
  assert.doesNotMatch(fs.readFileSync('cloudflare/src/initiatives-postgres.ts', 'utf8'), /progress.*amount_units/);
});

test('Programs require time-based execution while Projects may settle at funding', () => {
  assert.match(action, /Programs require timed execution/);
  assert.match(action, /Programs require a positive execution duration/);
  assert.match(action, /Funding-only initiatives cannot declare an execution duration/);
  assert.match(proposalActions, /Program initiatives require a positive execution duration/);
});

test('legacy initiative creation and treasury-routing paths are absent', () => {
  assert.doesNotMatch(legacyPrograms, /export async function createGlobalProgram/);
  assert.doesNotMatch(legacyPrograms, /export async function fundGlobalProgram/);
  assert.doesNotMatch(legacyProjects, /export async function createPublicProject/);
  assert.doesNotMatch(legacyProjects, /export async function fundMatchingPool/);
});

test('Initiatives require typed outcomes and apply them through explicit subsystem bridges', () => {
  for (const type of ['ECONOMIC_MODIFIER', 'SERVICE_CAPACITY', 'TECHNOLOGY_EFFECT', 'CAPACITY_EFFECT', 'PUBLIC_ASSET', 'PRESTIGE']) assert.match(outcomes, new RegExp(type));
  assert.match(outcomeMigration, /initiative_effect_applications/);
  assert.match(outcomes, /INSERT INTO world_conditions/);
  assert.match(outcomes, /INSERT INTO initiative_effect_applications/);
  assert.match(fs.readFileSync('cloudflare/src/initiatives-postgres.ts', 'utf8'), /applyInitiativeOutcome/);
  assert.doesNotMatch(fs.readFileSync('db/migrations/154_migrate_legacy_initiatives.sql', 'utf8'), /PLANETARY_PROGRAM_OUTPUT/);
});

test('treasury and matching funding are Governance commitments consumed by Settlement', () => {
  assert.match(fundingMigration, /commitment_type TEXT/);
  assert.match(fundingMigration, /'TREASURY','MATCHING'/);
  assert.match(materializer, /initiative-commitment:treasury/);
  assert.match(materializer, /initiative-commitment:matching/);
  const initiatives = fs.readFileSync('cloudflare/src/initiatives-postgres.ts', 'utf8');
  assert.match(initiatives, /initiative-funding:/);
  assert.match(initiatives, /INITIATIVE_TREASURY_FUNDING/);
  assert.match(initiatives, /INITIATIVE_MATCHING_FUNDING/);
  assert.match(initiatives, /initiative-refund:/);
  assert.match(initiatives, /status = 'RELEASED'/);
});

test('Initiative contribution quote and lifecycle events are auditable', () => {
  const initiatives = fs.readFileSync('cloudflare/src/initiatives-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
  const registry = fs.readFileSync('cloudflare/src/api-registry.ts', 'utf8');
  for (const field of ['walletBeforeUnits', 'walletAfterUnits', 'projectedMatchingUnits', 'remainingFundingRequirementUnits', 'deadlineGameDay']) assert.match(initiatives, new RegExp(field));
  assert.match(routes, /contribution-quote/);
  assert.match(registry, /quoteInitiativeContribution/);
  for (const event of ['INITIATIVE_CONTRIBUTION_ESCROWED', 'INITIATIVE_CONTRIBUTION_REFUNDED', 'INITIATIVE_MATCHING_FUNDING', 'INITIATIVE_EXECUTION_COMPLETED']) assert.match(initiatives, new RegExp(event));
  assert.match(initiatives, /postEconomicTransaction/);
  assert.match(initiatives, /postSettlementTransaction/);
});
