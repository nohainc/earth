import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { calculateProgressiveCharge, validateProgressiveBrackets } from '../cloudflare/src/v5-progressive.ts';
import { aggregateCorporationCapacity, calculateHouseCapacity, quoteCapacityChange, requiredTerritoryUnits } from '../cloudflare/src/v5-capacity.ts';
import { previewConstitutionAmendment, previewProgressivePolicyChange, validateV5FutureEffectiveDay, validateV5GovernanceAction } from '../cloudflare/src/v5-governance.ts';
import { runV5ShadowSimulation } from '../cloudflare/src/v5-shadow-simulation.ts';
import { CONSTITUTIONAL_RULE_DEFINITIONS, resolveConstitutionalRuleSet, validateConstitutionalRuleValue } from '../cloudflare/src/v5-constitution.ts';
import { evaluateOneHouseVote } from '../cloudflare/src/governance-decision.ts';

const brackets = [
  { ordinal: 1, lowerBound: 0n, upperBound: 1n, multiplierNumerator: 1n, multiplierDenominator: 1n },
  { ordinal: 2, lowerBound: 1n, upperBound: 2n, multiplierNumerator: 6n, multiplierDenominator: 5n },
  { ordinal: 3, lowerBound: 2n, upperBound: 4n, multiplierNumerator: 3n, multiplierDenominator: 2n },
  { ordinal: 4, lowerBound: 4n, upperBound: null, multiplierNumerator: 2n, multiplierDenominator: 1n },
];

test('V5 migration defines additive policy, obligation, admission, and container authorities', async () => {
  const migration = await readFile('db/migrations/083_v5_progressive_capacity_foundation.sql', 'utf8');
  for (const table of ['progressive_policy_schedules', 'progressive_policy_brackets', 'v5_capacity_policy_versions', 'corporation_capacity_state_v5', 'house_capacity_statements_v5', 'v5_capacity_obligations', 'v5_capacity_delinquency_state', 'corporation_membership_applications_v5', 'corporation_invites_v5', 'v5_corporation_founding_policy_versions']) assert.match(migration, new RegExp(`CREATE TABLE ${table}`));
  assert.match(migration, /financial_obligations_obligation_type_check/);
  assert.match(migration, /Active V5 progressive schedules are immutable/);
  assert.match(migration, /UPDATE corporations SET admission_policy = 'APPROVAL'/);
});

test('V5 structural settlement profiles are rebuildable and independent Houses route directly to Earth', async () => {
  const migration = await readFile(new URL('../db/migrations/093_v5_settlement_profiles.sql', import.meta.url), 'utf8');
  const profiles = await readFile(new URL('../cloudflare/src/v5-settlement-profiles-postgres.ts', import.meta.url), 'utf8');
  const capacity = await readFile(new URL('../cloudflare/src/v5-capacity-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /CREATE TABLE v5_house_settlement_profiles/);
  assert.match(migration, /CREATE TABLE v5_corporation_settlement_profiles/);
  assert.match(profiles, /rebuildV5HouseSettlementProfile/);
  assert.match(profiles, /rebuildV5CorporationSettlementProfile/);
  assert.match(migration, /dirty BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(capacity, /member\.corporationId === null/);
  assert.match(capacity, /'ECON-EARTH-001'/);
  assert.doesNotMatch(capacity, /SUM\(bc\.slot_footprint\)/);
});

test('V5 progressive pricing charges marginal quantities only', () => {
  const result = calculateProgressiveCharge({ quantity: 5n, baseRate: 100n, brackets });
  assert.equal(result.totalCharge, 720n);
  assert.deepEqual(result.allocations.map((item) => [item.ordinal, item.quantity, item.charge]), [[1, 1n, 100n], [2, 1n, 120n], [3, 2n, 300n], [4, 1n, 200n]]);
  assert.equal(calculateProgressiveCharge({ quantity: 4n, baseRate: 100n, brackets }).totalCharge, 520n);
  assert.equal(calculateProgressiveCharge({ quantity: 0n, baseRate: 100n, brackets }).totalCharge, 0n);
});

test('V5 progressive schedules reject gaps, repricing order, and closed tails', () => {
  assert.throws(() => validateProgressiveBrackets([{ ...brackets[0] }, { ...brackets[1], lowerBound: 3n, upperBound: 4n }]), /contiguous/);
  assert.throws(() => validateProgressiveBrackets([{ ...brackets[0], upperBound: null }, brackets[1]]), /final/);
  assert.throws(() => validateProgressiveBrackets([{ ...brackets[0] }, { ...brackets[1], multiplierNumerator: 1n, multiplierDenominator: 2n }, brackets[2], brackets[3]]), /non-decreasing/);
});

test('V5 capacity uses one residential unit and canonical billable footprints', () => {
  const house = calculateHouseCapacity({ houseId: 'H1', corporationId: 'C1', activeAffiliation: true, buildings: [
    { id: 'B1', footprint: 3n, billable: true },
    { id: 'B2', footprint: 99n, billable: false },
  ] });
  assert.deepEqual(house, { houseId: 'H1', corporationId: 'C1', residentialUnits: 1n, buildingUnits: 3n, totalUnits: 4n });
  const independentHouse = calculateHouseCapacity({ houseId: 'H2', corporationId: null, activeAffiliation: false, buildings: [] });
  assert.equal(independentHouse.residentialUnits, 1n);
  assert.equal(independentHouse.totalUnits, 1n);
  const aggregate = aggregateCorporationCapacity({ corporationId: 'C1', houses: [house], publicBuildingUnits: 1n, standardTerritoryCapacity: 5n });
  assert.equal(aggregate.totalOccupiedUnits, 5n);
  assert.equal(aggregate.requiredTerritoryUnits, 1n);
  assert.equal(aggregate.memberCount, 1n);
});

test('V5 Territory containers scale at exact boundaries', () => {
  assert.deepEqual([requiredTerritoryUnits(0n, 10n), requiredTerritoryUnits(10n, 10n), requiredTerritoryUnits(11n, 10n)], [0n, 1n, 2n]);
  assert.throws(() => requiredTerritoryUnits(1n, 0n), /positive/);
});

test('V5 capacity quote is the exact marginal delta and supports release', () => {
  const quote = quoteCapacityChange({ currentUsage: 4n, delta: 1n, baseRate: 100n, brackets });
  assert.equal(quote.currentCharge.totalCharge, 520n);
  assert.equal(quote.afterCharge.totalCharge, 720n);
  assert.equal(quote.incrementalCharge, 200n);
  assert.equal(quoteCapacityChange({ currentUsage: 5n, delta: -1n, baseRate: 100n, brackets }).afterUsage, 4n);
  assert.throws(() => quoteCapacityChange({ currentUsage: 0n, delta: -1n, baseRate: 100n, brackets }), /negative/);
});

test('V5 suspension is non-destructive and reversible', async () => {
  const migration = await readFile(new URL('../db/migrations/083_v5_progressive_capacity_foundation.sql', import.meta.url), 'utf8');
  assert.match(migration, /v5_productive_status TEXT NOT NULL DEFAULT 'ACTIVE'/);
  assert.match(migration, /v5_productive_status IN \('ACTIVE','SUSPENDED'\)/);
  const settlement = await readFile(new URL('../cloudflare/src/v5-capacity-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /PRODUCTIVE_CAPACITY_SUSPENDED/);
  assert.match(settlement, /v5_productive_status = \$2/);
  const buildingSettlement = await readFile(new URL('../cloudflare/src/building-settlement-v2.ts', import.meta.url), 'utf8');
  assert.match(buildingSettlement, /COALESCE\(b\.v5_productive_status, 'ACTIVE'\) = 'ACTIVE'/);
});

test('V5 corporation distress guards discretionary expansion', async () => {
  const fiscal = await readFile(new URL('../cloudflare/src/corporation-fiscal-postgres.ts', import.meta.url), 'utf8');
  assert.match(fiscal, /EARTH_RECEIVERSHIP/);
  assert.match(fiscal, /blocks discretionary spending/);
  const construction = await readFile(new URL('../cloudflare/src/territory-capacity-postgres.ts', import.meta.url), 'utf8');
  assert.match(construction, /blocks public expansion/);
});

test('V5 House finance response exposes capacity statements and obligations', async () => {
  const routes = await readFile(new URL('../cloudflare/src/finance-routes.ts', import.meta.url), 'utf8');
  assert.match(routes, /getV5HouseCapacity/);
  assert.match(routes, /v5_capacity_obligations/);
  assert.match(routes, /capacity: \{ summary: v5Capacity, obligations: v5Obligations\.rows \}/);
});

test('V5 governance validates future policies and previews proposed brackets', () => {
  assert.throws(() => validateV5FutureEffectiveDay(5, 5), /future game day/);
  assert.throws(() => validateV5GovernanceAction({ actionType: 'PROGRESSIVE_SCHEDULE', effectiveFromGameDay: 6, authorityInstitutionId: 'CORP-1', scheduleCode: 'bad', scheduleBasisType: 'CORPORATION_HOUSE_CAPACITY', brackets: [{ ordinal: 1, lowerBound: 0n, upperBound: 1n, multiplierNumerator: 2n, multiplierDenominator: 1n }] }, 5), /open-ended/);
  const proposed = [...brackets];
  proposed[1] = { ...proposed[1], multiplierNumerator: 3n, multiplierDenominator: 2n };
  const preview = previewProgressivePolicyChange({ quantities: [1n, 2n, 5n], baseRate: 100n, currentBrackets: brackets, proposedBrackets: proposed });
  assert.equal(preview.length, 3);
  assert.equal(preview[0].delta, 0n);
  assert.ok(preview[2].delta > 0n);
});

test('Constitution amendment preview applies typed changes and restores Earth defaults when clearing overrides', () => {
  const preview = previewConstitutionAmendment({
    currentRules: { 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS': 4000n },
    fallbackRules: { 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS': 2500n },
    changes: [{ ruleCode: 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS', clearOverride: true }],
  });
  assert.equal(preview.changes[0].currentValue, 4000n);
  assert.equal(preview.changes[0].proposedValue, 2500n);
  assert.equal(preview.proposedRules['CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS'], 2500n);
});

test('V4 and V5 share strict one-House voting semantics', () => {
  assert.equal(evaluateOneHouseVote({ support: 1, oppose: 1, abstain: 2, electorateSize: 4, quorumBps: 5000, approvalBps: 5000 }).quorumMet, true);
  assert.equal(evaluateOneHouseVote({ support: 1, oppose: 1, abstain: 2, electorateSize: 4, quorumBps: 5000, approvalBps: 5000 }).passed, false);
  assert.equal(evaluateOneHouseVote({ support: 1, oppose: 0, abstain: 1, electorateSize: 4, quorumBps: 5000, approvalBps: 5000 }).quorumMet, true);
  assert.equal(evaluateOneHouseVote({ support: 1, oppose: 0, abstain: 1, electorateSize: 4, quorumBps: 5000, approvalBps: 5000 }).passed, true);
});

test('V4 proposal rules freeze the electorate denominator at creation', async () => {
  const source = await readFile(new URL('../cloudflare/src/governance-v4-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /electorateSnapshotGameDay/);
  assert.match(source, /electorateSize: Number\(electorate\.rows\[0\]\?\.count/);
  assert.match(source, /electorateSize: Number\(ruleSnapshot\.electorateSize/);
  assert.doesNotMatch(source, /const electorate = proposal\.subject_type/);
});

test('V4 ballot authorization uses an exact persisted electorate snapshot', async () => {
  const migration = await readFile(new URL('../db/migrations/108_v4_electorate_snapshots.sql', import.meta.url), 'utf8');
  const source = await readFile(new URL('../cloudflare/src/governance-v4-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /governance_electorate_snapshots_v4/);
  assert.match(source, /INSERT INTO governance_electorate_snapshots_v4/);
  assert.match(source, /FROM house_affiliations/);
  assert.match(source, /FROM governance_electorate_snapshots_v4 WHERE proposal_id = \$1 AND house_id = \$2/);
  assert.match(source, /House was not in the frozen V4 electorate/);
});

test('V4 ballot totals cannot be inflated by duplicate casts', async () => {
  const source = await readFile(new URL('../cloudflare/src/governance-v4-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /governance_ballots_v4[\s\S]*ON CONFLICT \(proposal_id, house_id\) DO NOTHING/);
  assert.match(source, /if \(ballot\.rowCount !== 1\) throw new Error\('Ballot already recorded'\)/);
});

test('proposal execution rejects unregistered action handlers', async () => {
  const actions = await readFile(new URL('../cloudflare/src/proposal-actions.ts', import.meta.url), 'utf8');
  assert.match(actions, /Unregistered proposal action handler/);
  assert.doesNotMatch(actions, /handlers\.get\([^\n]+\) \?\?/);
});

test('V5 constitutional rules enforce typed values and authority inheritance', () => {
  assert.ok(CONSTITUTIONAL_RULE_DEFINITIONS.some((rule) => rule.code === 'EARTH.CAPACITY.STANDARD'));
  assert.ok(CONSTITUTIONAL_RULE_DEFINITIONS.every((rule) => ['FOUNDATIONAL', 'POLICY', 'LOCAL_POLICY', 'OPERATIONAL'].includes(rule.amendmentClass)));
  validateConstitutionalRuleValue('EARTH.CAPACITY.STANDARD', 10n);
  validateConstitutionalRuleValue('CORPORATION.ADMISSION_POLICY', 'OPEN');
  validateConstitutionalRuleValue('EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', brackets);
  assert.throws(() => validateConstitutionalRuleValue('EARTH.CAPACITY.STANDARD', 0n), /Invalid value/);
  assert.throws(() => validateConstitutionalRuleValue('CORPORATION.ADMISSION_POLICY', 'PUBLIC'), /Invalid value/);
  const earth = {
    'EARTH.CAPACITY.BASE_RATE': 100n,
    'CORPORATION.HOUSE_CAPACITY.BASE_RATE': 50n,
    'CORPORATION.ADMISSION_POLICY': 'OPEN',
  };
  const corporation = {
    'CORPORATION.HOUSE_CAPACITY.BASE_RATE': 75n,
    'CORPORATION.ADMISSION_POLICY': 'INVITE_ONLY',
  };
  const resolved = resolveConstitutionalRuleSet({ earth, corporation });
  assert.equal(resolved['CORPORATION.HOUSE_CAPACITY.BASE_RATE'], 75n);
  assert.equal(resolved['CORPORATION.ADMISSION_POLICY'], 'INVITE_ONLY');
  assert.equal(resolveConstitutionalRuleSet({ earth })['CORPORATION.HOUSE_CAPACITY.BASE_RATE'], 50n);
});

test('V5 governance snapshots and strict decision semantics are persisted in the migration', async () => {
  const migration = await readFile(new URL('../db/migrations/094_v5_governance_snapshots.sql', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /electorate_snapshot_game_day/);
  assert.match(migration, /governance_rule_snapshot/);
  assert.match(migration, /base_version_snapshot/);
  assert.match(service, /abstain_votes/);
  assert.match(service, /evaluateOneHouseVote/);
  assert.match(service, /electorate_size/);
  assert.match(service, /joined_game_day <=/);
});

test('V5 constitutional amendments are typed, policy-group scoped change sets', async () => {
  const governance = await readFile(new URL('../cloudflare/src/v5-governance.ts', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/095_constitution_kernel.sql', import.meta.url), 'utf8');
  assert.match(governance, /CONSTITUTION_AMENDMENT/);
  assert.match(service, /materializeConstitutionSchedule/);
  assert.match(service, /earth_validate_v5_progressive_schedule/);
  assert.match(governance, /validateConstitutionalRuleValue/);
  assert.match(service, /constitutional_change_sets_v5/);
  assert.match(service, /groups\.size !== 1/);
  assert.match(service, /status = 'RETIRED'/);
  assert.match(service, /CORPORATION\.ADMISSION_POLICY/);
  assert.match(service, /proposalInputPayload/);
  assert.match(service, /governancePolicy\(tx/);
  assert.match(service, /implementationDelayDays/);
  assert.match(service, /voting_start_game_day/);
  assert.match(migration, /CREATE TABLE constitutional_change_sets_v5/);
});

test('V5 Constitution activation rolls back a failed change set atomically', async () => {
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /SAVEPOINT \$\{savepoint\}/);
  assert.match(service, /ROLLBACK TO SAVEPOINT/);
  assert.match(service, /RELEASE SAVEPOINT/);
  assert.match(service, /A Constitution change set is atomic/);
});

test('V5 override clearing is restricted to Corporation scope', async () => {
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /Only a Corporation can clear its Earth-default override/);
});

test('V5 active policy-group exclusivity is enforced by PostgreSQL', async () => {
  const migration = await readFile(new URL('../db/migrations/104_v5_governance_policy_group_lock.sql', import.meta.url), 'utf8');
  assert.match(migration, /CREATE UNIQUE INDEX v5_governance_one_active_policy_group_idx/);
  assert.match(migration, /COALESCE\(subject_id, ''\)/);
  assert.match(migration, /status IN \('VOTING', 'PASSED', 'SCHEDULED'\)/);
});

test('V5 amendments lock both existing and absent base versions', async () => {
  const source = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /baseVersionSnapshot\[code\] = null/);
  assert.match(source, /Object\.prototype\.hasOwnProperty\.call\(base, change\.ruleCode\)/);
  assert.match(source, /current\?\.id \?\? null/);
});

test('V5 rule definitions expose stable calculation dispatch keys', async () => {
  const registry = await readFile(new URL('../cloudflare/src/v5-constitution.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/105_constitution_calculation_keys.sql', import.meta.url), 'utf8');
  const readModel = await readFile(new URL('../cloudflare/src/constitutional-kernel-postgres.ts', import.meta.url), 'utf8');
  assert.match(registry, /calculationKey: string/);
  assert.match(registry, /earth\.capacity\.base_rate/);
  assert.match(migration, /calculation_key TEXT/);
  assert.match(migration, /SET calculation_key = CASE rule_code/);
  assert.match(migration, /calculation_key SET NOT NULL/);
  assert.match(readModel, /amendment_class, calculation_key, allowed_values/);
});

test('V5 resolved Constitution snapshots persist authority provenance', async () => {
  const migration = await readFile(new URL('../db/migrations/106_constitution_snapshot_provenance.sql', import.meta.url), 'utf8');
  const kernel = await readFile(new URL('../cloudflare/src/constitutional-kernel-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /provenance_json JSONB/);
  assert.match(kernel, /provenance: Record<string, 'EARTH' \| 'CORPORATION'>/);
  assert.match(kernel, /provenance_json/);
  assert.match(kernel, /provenance: resolved.provenance/);
});

test('V5 Constitution snapshots are immutable once materialized', async () => {
  const kernel = await readFile(new URL('../cloudflare/src/constitutional-kernel-postgres.ts', import.meta.url), 'utf8');
  assert.match(kernel, /ON CONFLICT \(authority_type, authority_id, game_day\) DO NOTHING/);
  assert.match(kernel, /Constitution snapshot disappeared after conflict/);
  assert.match(kernel, /SELECT id, version_ids/);
  assert.doesNotMatch(kernel, /ON CONFLICT \(authority_type, authority_id, game_day\) DO UPDATE/);
});

test('Constitution resolver preserves retired versions for historical game-day replay', async () => {
  const kernel = await readFile(new URL('../cloudflare/src/constitutional-kernel-postgres.ts', import.meta.url), 'utf8');
  assert.match(kernel, /v\.status IN \('ACTIVE', 'RETIRED'\)/);
  assert.match(kernel, /effective_to_game_day IS NULL OR v\.effective_to_game_day >= \$3/);
});

test('V5 persisted policy groups match the canonical runtime registry', async () => {
  const migration = await readFile(new URL('../db/migrations/107_normalize_constitution_policy_groups.sql', import.meta.url), 'utf8');
  assert.match(migration, /SET policy_group = CASE/);
  assert.match(migration, /THEN 'CAPACITY_POLICY'/);
  assert.match(migration, /THEN 'EARTH_HOUSE_INCOME_TAX'/);
  assert.match(migration, /THEN 'CORPORATION_HOUSE_INCOME_TAX'/);
});

test('V5 daily settlement materializes one resolved Constitution per active authority', async () => {
  const scheduler = await readFile(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
  const phases = await readFile(new URL('../cloudflare/src/daily-settlement-phases.ts', import.meta.url), 'utf8');
  const kernel = await readFile(new URL('../cloudflare/src/constitutional-kernel-postgres.ts', import.meta.url), 'utf8');
  assert.match(phases, /required\('constitution_snapshots'/);
  assert.match(scheduler, /materializeResolvedConstitutionSnapshot/);
  assert.match(scheduler, /FROM corporations WHERE status = 'ACTIVE'/);
  assert.match(kernel, /resolved_constitution_snapshots_v5/);
});

test('V5 capacity settlement consumes resolved Constitution values before legacy policy fallback', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/v5-capacity-settlement-postgres.ts', import.meta.url), 'utf8');
  const quotes = await readFile(new URL('../cloudflare/src/v5-capacity-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /resolved_constitution_snapshots_v5/);
  assert.match(quotes, /resolved_constitution_snapshots_v5/);
  assert.match(settlement, /EARTH\.CAPACITY\.STANDARD/);
  assert.match(settlement, /CORPORATION\.HOUSE_CAPACITY\.BASE_RATE/);
  assert.match(settlement, /rulesVersion: string/);
  assert.match(settlement, /ruleSetId: snapshot\.id/);
  assert.match(settlement, /rules_version = EXCLUDED\.rules_version/);
  assert.match(settlement, /snapshotFields/);
  assert.match(settlement, /snapshotFields\.every/);
  assert.match(quotes, /snapshotRules\['EARTH\.CAPACITY\.STANDARD'\]/);
  assert.match(quotes, /corporationScheduleId/);
});

test('daily tax settlement consumes the assessed-day Constitution market rate', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /resolved_constitution_snapshots_v5/);
  assert.match(settlement, /EARTH\.MARKET\.TRANSACTION_TAX_RATE/);
  assert.match(settlement, /constitutionalRate\(rule\)/);
  assert.match(settlement, /CORPORATION\.TAX\.INCOME_RATE/);
  assert.match(settlement, /EARTH\.TAX\.BASIC_LEVY_RATE/);
  assert.match(settlement, /corporationMemberships/);
  assert.match(settlement, /nexus_type: 'MEMBERSHIP'/);
});

test('House and Corporation fiscal read models expose canonical tax rules and provenance', async () => {
  const house = await readFile(new URL('../cloudflare/src/tax-statement-postgres.ts', import.meta.url), 'utf8');
  const corporation = await readFile(new URL('../cloudflare/src/corporation-fiscal-postgres.ts', import.meta.url), 'utf8');
  assert.match(house, /constitutionalTaxRules/);
  assert.match(house, /constitutionalTaxVersionIds/);
  assert.match(house, /resolveEffectiveConstitution/);
  assert.match(corporation, /taxRulesSource/);
  assert.match(corporation, /constitution-snapshot-v5/);
  assert.match(corporation, /constitutionalTaxVersionIds/);
  const financeRoutes = await readFile(new URL('../cloudflare/src/finance-routes.ts', import.meta.url), 'utf8');
  assert.match(financeRoutes, /canonicalTaxStatement/);
  assert.match(financeRoutes, /postgres-constitutional-tax-v5/);
});

test('Corporation tax settlement selects canonical rates and rule provenance', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/corporation-tax-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /COALESCE\(\(snap\.rules_json->>'CORPORATION\.TAX\.CORPORATE_RATE'/);
  assert.match(settlement, /snap\.version_ids->>'CORPORATION\.TAX\.CORPORATE_RATE'/);
  assert.match(settlement, /corporation\.tax_rule_version/);
  assert.match(settlement, /earth_post_transaction\(\$1,\$2,1439/);
  assert.doesNotMatch(settlement, /corporation-tax-v4/);
});

test('V5 Constitution read model exposes resolved values, provenance, and history', async () => {
  const kernel = await readFile(new URL('../cloudflare/src/constitutional-kernel-postgres.ts', import.meta.url), 'utf8');
  const route = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  const client = await readFile(new URL('../flutter_client/lib/core/api/earth_api_governance.dart', import.meta.url), 'utf8');
  assert.match(kernel, /getConstitutionReadModel/);
  assert.match(kernel, /versionIds/);
  assert.match(kernel, /effective_to_game_day/);
  assert.match(kernel, /Keep Constitution responses JSON-safe/);
  assert.match(kernel, /rules: toJsonSafe\(resolved\.rules\)/);
  assert.match(kernel, /scheduledChanges/);
  assert.match(route, /governance\/v5\/constitution/);
  assert.match(route, /constitution\/preview/);
  assert.match(client, /getV5Constitution/);
});

test('legacy player-facing constitutional mutation routes are retired', async () => {
  const organizations = await readFile(new URL('../cloudflare/src/organizations-routes.ts', import.meta.url), 'utf8');
  const governance = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  const institutions = await readFile(new URL('../cloudflare/src/institutions-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  assert.match(organizations, /Direct Charter mutation is retired/);
  assert.match(governance, /Direct voting-setting mutation is retired/);
  assert.match(governance, /Direct rule mutation is retired/);
  assert.match(institutions, /Direct Corporation tax mutation is retired/);
  assert.match(institutions, /Direct admission-policy mutation is retired/);
  assert.match(registry, /charter\/amend[^\n]+status: 'RETIRED'/);
  assert.match(registry, /tax-charter[^\n]+status: 'RETIRED'/);
  assert.match(governance, /Legacy tax governance is retired/);
});

test('V5 resolution cases preserve Houses and release only selected building capacity', async () => {
  const migration = await readFile(new URL('../db/migrations/085_v5_capacity_resolution_cases.sql', import.meta.url), 'utf8');
  assert.match(migration, /v5_capacity_resolution_cases/);
  assert.match(migration, /v5_capacity_resolution_assets/);
  const service = await readFile(new URL('../cloudflare/src/v5-capacity-resolution-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /status = 'INACTIVE'/);
  assert.match(service, /V5_CAPACITY_ASSET_RELEASED/);
  assert.doesNotMatch(service, /DELETE FROM houses/);
});

test('V5 Corporation receivership is auditable and preserves member Houses', async () => {
  const migration = await readFile(new URL('../db/migrations/086_v5_corporation_receivership.sql', import.meta.url), 'utf8');
  assert.match(migration, /v5_corporation_receivership_cases/);
  assert.match(migration, /v5_corporation_restructuring_plans/);
  const settlement = await readFile(new URL('../cloudflare/src/v5-capacity-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /ensureCorporationReceivershipCase/);
  const service = await readFile(new URL('../cloudflare/src/v5-corporation-receivership-postgres.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(service, /DELETE FROM houses/);
  assert.match(service, /RESTRUCTURING/);
});

test('V5 technology research exposes catalog-authoritative duration and quote flow', async () => {
  const migration = await readFile(new URL('../db/migrations/087_v5_technology_duration.sql', import.meta.url), 'utf8');
  assert.match(migration, /research_duration_game_days/);
  const service = await readFile(new URL('../cloudflare/src/technology-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /quoteResearchProject/);
  assert.match(service, /researchDurationGameDays/);
  assert.match(service, /credit_cost_units::TEXT AS research_credit_cost_units/);
  const route = await readFile(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');
  assert.match(route, /\/api\/technology\/projects\/quote/);
});

test('V5 research settlement advances projects and grants access on completion', async () => {
  const service = await readFile(new URL('../cloudflare/src/technology-postgres.ts', import.meta.url), 'utf8');
  const scheduler = await readFile(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /advanceV5ResearchProjects/);
  assert.match(service, /progress_research_points = \$1/);
  assert.match(service, /completed_game_day = \$1/);
  assert.match(service, /earth_grant_corporation_technology_access/);
  assert.match(scheduler, /v5: await advanceV5ResearchProjects/);
});

test('V5 market order ticket uses a server quote contract', async () => {
  const service = await readFile(new URL('../cloudflare/src/market-api.ts', import.meta.url), 'utf8');
  assert.match(service, /\/api\/market\/order-quote/);
  assert.match(service, /calculateFeeUnits/);
  assert.match(service, /reservedUnits/);
  const client = await readFile(new URL('../flutter_client/lib/features/market/market_panels.dart', import.meta.url), 'utf8');
  assert.match(client, /quoteOrder/);
  assert.match(client, /SERVER QUOTE/);
});

test('V5 governance read model is scoped to Earth and active Corporation affiliation', async () => {
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /listV5GovernanceProposals/);
  assert.match(service, /subject_type = 'EARTH'/);
  assert.match(service, /house_affiliations/);
  assert.match(service, /viewer_voted/);
  const route = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  assert.match(route, /governance\/v5\/proposals.*GET/);
});

test('V5 public governance accepts only typed Constitution amendment change sets', async () => {
  const route = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  assert.match(route, /actionType\?: 'CONSTITUTION_AMENDMENT'/);
  assert.doesNotMatch(route, /actionType\?: 'CONSTITUTION_AMENDMENT' \| 'EARTH_CAPACITY_POLICY'/);
});

test('V5 Finance exposes server-authoritative liquidity and next settlement', async () => {
  const route = await readFile(new URL('../cloudflare/src/finance-routes.ts', import.meta.url), 'utf8');
  const client = await readFile(new URL('../flutter_client/lib/features/finance/personal_finance_panel.dart', import.meta.url), 'utf8');
  assert.match(route, /availableToSpendUnits/);
  assert.match(route, /nextSettlementGameDay/);
  assert.match(client, /serverAvailableToSpend/);
  assert.match(client, /nextSettlementGameDay/);
});

test('V5 shadow simulation is deterministic and measures arrears and standardized capacity', async () => {
  const source = await readFile(new URL('../cloudflare/src/v5-shadow-simulation.ts', import.meta.url), 'utf8');
  assert.match(source, /runV5ShadowSimulation/);
  assert.match(source, /totalHouseArrearsUnits/);
  assert.match(source, /requiredTerritoryUnits/);
  assert.match(source, /calculateProgressiveCharge/);
  assert.match(source, /never writes production state|never writes production/i);
  const input = {
    days: 3,
    corporations: [{ id: 'CORP-A', startingWalletUnits: 0n, dailyIncomeUnits: 0n }],
    houses: [{ id: 'HOUSE-A', corporationId: 'CORP-A', occupiedUnits: 2n, startingWalletUnits: 5n, dailyIncomeUnits: 0n, active: true }],
    policy: {
      standardTerritoryCapacityUnits: 2n,
      earthBaseRateUnits: 1n,
      earthBrackets: brackets,
      houseBaseRateByCorporation: { 'CORP-A': 2n },
      houseBrackets: brackets,
    },
  };
  const first = runV5ShadowSimulation(input);
  const second = runV5ShadowSimulation(input);
  assert.deepEqual(first, second);
  assert.equal(first.peakRequiredTerritoryUnits, 1n);
  assert.ok(first.totalHouseArrearsUnits > 0n);
  assert.ok(first.metrics.houseSurvivalRateBps > 0n);
  assert.equal(first.metrics.totalEarthRevenueUnits, first.days.reduce((sum, day) => sum + day.earthPaidUnits, 0n));
  assert.equal(first.metrics.corporationConcentrationBps, 10_000n);
});

test('V5 capacity backfill is resumable, shadow-only, and reportable', async () => {
  const migration = await readFile(new URL('../db/migrations/088_v5_capacity_backfill_runs.sql', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/v5-capacity-backfill-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /v5_capacity_backfill_runs/);
  assert.match(service, /backfillV5CapacityBatch/);
  assert.match(service, /ON CONFLICT \(corporation_id, game_day\) DO UPDATE/);
  assert.match(service, /paid_rent_units,\n             arrears_units/);
  assert.doesNotMatch(service, /earth_post_transaction/);
  const routes = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  assert.match(routes, /internal\/v5\/capacity-backfill/);
});

test('V5 cutover readiness is fail-closed and read-only', async () => {
  const service = await readFile(new URL('../cloudflare/src/v5-cutover-readiness-postgres.ts', import.meta.url), 'utf8');
  const routes = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  assert.match(service, /capacityBackfillCompleted/);
  assert.match(service, /schemaVersionMatches/);
  assert.match(service, /allActiveCorporationsHavePolicy/);
  assert.match(service, /allActiveCorporationsHaveConstitutionSnapshot/);
  assert.match(service, /constitutionalDefinitionsPresent/);
  assert.match(service, /taxReconciliationClean/);
  assert.match(service, /mutationEnabled: false/);
  assert.match(service, /Object\.values\(checks\)\.every\(Boolean\)/);
  assert.doesNotMatch(service, /INSERT INTO|UPDATE |DELETE FROM/);
  assert.match(routes, /internal\/v5\/cutover-readiness/);
  const reconciliation = await readFile(new URL('../cloudflare/src/v5-tax-reconciliation-postgres.ts', import.meta.url), 'utf8');
  assert.match(reconciliation, /v5_tax_reconciliation_items/);
  assert.match(reconciliation, /reconciliation-only/);
  const migration = await readFile(new URL('../db/migrations/103_v5_tax_reconciliation.sql', import.meta.url), 'utf8');
  assert.match(migration, /v5_tax_reconciliation_runs/);
  assert.match(migration, /MISSING_CANONICAL/);
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  const readRoutes = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  assert.match(registry, /internal\/v5\/tax-reconciliation/);
  assert.match(readRoutes, /getV5TaxReconciliation/);
});

test('V5 pooled construction accepts no Territory placement target', async () => {
  const migration = await readFile(new URL('../db/migrations/089_v5_pooled_construction.sql', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/v5-building-postgres.ts', import.meta.url), 'utf8');
  const route = await readFile(new URL('../cloudflare/src/real-estate-routes.ts', import.meta.url), 'utf8');
  assert.match(migration, /ALTER TABLE buildings ALTER COLUMN territory_id DROP NOT NULL/);
  assert.match(service, /territoryPlacement: null/);
  assert.match(service, /V5_POOLED_CONSTRUCTION/);
  assert.match(route, /\/api\/v5\/buildings/);
});

test('V5 building research uses authored catalog economics', async () => {
  const migration = await readFile(new URL('../db/migrations/091_v5_building_research_catalog_authority.sql', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/corporation-building-research-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /research_credit_units/);
  assert.match(migration, /research_duration_game_days/);
  assert.match(service, /target\.research_credit_units/);
  assert.match(service, /target\.research_duration_game_days/);
  assert.doesNotMatch(service, /function researchCost|function researchDurationDays|Math\.pow/);
});

test('V5 governance UI exposes only Earth and Corporation scopes', async () => {
  const panel = await readFile(new URL('../flutter_client/lib/features/governance/governance_panels.dart', import.meta.url), 'utf8');
  assert.match(panel, /TabController\(length: 2/);
  assert.match(panel, /Territory records are physical capacity containers/);
  assert.doesNotMatch(panel, /_scopeTab\(context, 0, 'TERRITORY/);
});

test('Constitution UI submits typed amendments through preview before proposal creation', async () => {
  const panel = await readFile(new URL('../flutter_client/lib/features/governance/constitution_panel.dart', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../flutter_client/lib/features/command_center/dashboard.dart', import.meta.url), 'utf8');
  assert.match(panel, /onProposeAmendment/);
  assert.match(panel, /PROPOSE AMENDMENT/);
  assert.match(panel, /value_type/);
  assert.match(dashboard, /previewV5ConstitutionAmendment/);
  assert.match(dashboard, /proposeV5ConstitutionAmendment/);
});

test('Constitution UI renders the canonical V5 registry instead of requiring legacy articles', async () => {
  const panel = await readFile(new URL('../flutter_client/lib/features/governance/constitution_panel.dart', import.meta.url), 'utf8');
  assert.match(panel, /canonicalDefinitions is List && canonicalDefinitions\.isNotEmpty/);
  assert.match(panel, /_resolveAllRules\(canonical\)/);
  assert.match(panel, /_categoryForArticle/);
  assert.match(panel, /hasCanonicalRules/);
});

test('V5 client finance projections consume server policy multipliers', async () => {
  const finance = await readFile(new URL('../flutter_client/lib/features/finance/personal_finance_panel.dart', import.meta.url), 'utf8');
  const institutions = await readFile(new URL('../flutter_client/lib/features/institutions/institutions_panels.dart', import.meta.url), 'utf8');
  assert.match(finance, /building\['output_multiplier'\]/);
  assert.match(finance, /building\['cost_multiplier'\]/);
  assert.match(institutions, /building\['output_multiplier'\]/);
  assert.doesNotMatch(`${finance}\n${institutions}`, /high_output|eco_reserve|frugal/);
});

test('V5 building client projections consume server policy multipliers', async () => {
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(buildings, /building\['output_multiplier'\]/);
  assert.match(buildings, /building\['cost_multiplier'\]/);
  assert.doesNotMatch(buildings, /high_output|eco_reserve|frugal/);
});

test('V5 cutover rehearsal is fail-closed and produces evidence', async () => {
  const script = await readFile(new URL('../scripts/run-v5-cutover-rehearsal.mjs', import.meta.url), 'utf8');
  assert.match(script, /DATABASE_URL is required for a V5 cutover rehearsal/);
  assert.match(script, /artifact_checks_passed_database_rehearsal_pending/);
  assert.match(script, /createHash\('sha256'\)/);
  assert.match(script, /db:verify:surface/);
  assert.match(script, /db:verify:readiness/);
});

test('V5 Territory view is read-only physical capacity context', async () => {
  const panel = await readFile(new URL('../flutter_client/lib/features/institutions/territory_overview_panel.dart', import.meta.url), 'utf8');
  assert.match(panel, /Read-only physical capacity-container overview/);
  assert.match(panel, /does not create a political or placement choice/);
  assert.doesNotMatch(panel, /MANAGE USE RIGHTS|Acquire or release use rights/);
});

test('V5 command overview converts PostgreSQL bigint values at the JSON boundary', async () => {
  const overview = await readFile(new URL('../cloudflare/src/v5-overview-postgres.ts', import.meta.url), 'utf8');
  assert.match(overview, /typeof value === 'bigint'/);
  assert.match(overview, /capacity: toJsonSafe\(capacity\)/);
  assert.match(overview, /latestStatement: toJsonSafe/);
  assert.match(overview, /Number\(delinquencyRow\.consecutive_missed_days/);
});

test('V5 corporation lifecycle supports name reuse, leadership delegation, and graceful dissolution', async () => {
  const founding = await readFile(new URL('../cloudflare/src/v5-founding-postgres.ts', import.meta.url), 'utf8');
  assert.match(founding, /lower\(name\) = lower\(\$1\) AND status = \\'ACTIVE\\'/);
  const membership = await readFile(new URL('../cloudflare/src/v5-membership-postgres.ts', import.meta.url), 'utf8');
  assert.match(membership, /delegateV5CorporationLeadership/);
  assert.match(membership, /scheduleV5CorporationDissolution/);
  assert.match(membership, /executePendingV5CorporationDissolutionsInTransaction/);
  assert.match(membership, /successor/);
  assert.match(membership, /CORPORATION_LEADERSHIP_DELEGATED/);
  assert.match(membership, /CORPORATION_DISSOLUTION_SCHEDULED/);
  const migration = await readFile(new URL('../db/migrations/092_v5_corporation_lifecycle_dissolution_name_reuse.sql', import.meta.url), 'utf8');
  assert.match(migration, /CREATE UNIQUE INDEX institutions_active_name_idx ON institutions \(lower\(name\)\) WHERE status = 'ACTIVE'/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS v5_corporation_dissolution_schedules/);
});
