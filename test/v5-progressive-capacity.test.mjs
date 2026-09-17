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

test('V5 settlement profiles exclude inactive Houses from residential aggregates', async () => {
  const profiles = await readFile(new URL('../cloudflare/src/v5-settlement-profiles-postgres.ts', import.meta.url), 'utf8');
  assert.match(profiles, /CASE WHEN \$7 = 'ACTIVE' THEN 1::BIGINT ELSE 0::BIGINT END/);
  assert.match(profiles, /JOIN houses h ON h\.id = hp\.house_id AND h\.status = 'ACTIVE'/);
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
  const electorateMigration = await readFile(new URL('../db/migrations/114_v5_electorate_snapshots.sql', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /electorate_snapshot_game_day/);
  assert.match(migration, /governance_rule_snapshot/);
  assert.match(migration, /base_version_snapshot/);
  assert.match(service, /abstain_votes/);
  assert.match(service, /evaluateOneHouseVote/);
  assert.match(service, /electorate_size/);
  assert.match(service, /joined_game_day <=/);
  assert.match(electorateMigration, /v5_governance_electorate_snapshots_v5/);
  assert.match(service, /INSERT INTO v5_governance_electorate_snapshots_v5/);
  assert.match(service, /FROM v5_governance_electorate_snapshots_v5 WHERE proposal_id = \$1 AND house_id = \$2/);
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

test('V5 Constitution amendments cannot reference a missing progressive schedule', async () => {
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /assertExistingProgressiveSchedule/);
  assert.match(service, /status = 'ACTIVE'/);
  assert.match(service, /Progressive schedule is not an active canonical policy/);
});

test('V5 Corporation admission consumes the canonical Constitution rule', async () => {
  const membership = await readFile(new URL('../cloudflare/src/v5-membership-postgres.ts', import.meta.url), 'utf8');
  const founding = await readFile(new URL('../cloudflare/src/v5-founding-postgres.ts', import.meta.url), 'utf8');
  assert.match(membership, /getResolvedConstitutionForDay/);
  assert.match(membership, /CORPORATION\.ADMISSION_POLICY/);
  assert.match(founding, /INSERT INTO constitutional_rule_versions_v5/);
  assert.match(founding, /CORPORATION\.ADMISSION_POLICY/);
  assert.match(founding, /CORPORATION\.HOUSE_CAPACITY\.BASE_RATE/);
  assert.doesNotMatch(founding, /INSERT INTO corporation_capacity_policy_versions/);
  assert.match(membership, /CORPORATION\.HOUSE_CAPACITY\.BASE_RATE/);
  assert.match(membership, /EARTH\.CAPACITY\.HOUSE_PROGRESSIVE_SCHEDULE/);
});

test('V5 exposes an Earth-wide capacity read model alongside House and Corporation views', async () => {
  const capacity = await readFile(new URL('../cloudflare/src/v5-capacity-postgres.ts', import.meta.url), 'utf8');
  const readiness = await readFile(new URL('../cloudflare/src/v5-cutover-readiness-postgres.ts', import.meta.url), 'utf8');
  const taxSettlement = await readFile(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');
  const routes = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  assert.match(capacity, /getV5EarthCapacity/);
  assert.match(capacity, /independentOccupiedUnits/);
  assert.match(capacity, /SUM\(total_capacity_units\) FILTER \(WHERE corporation_id IS NULL\)/);
  assert.match(capacity, /requiredTerritoryUnits/);
  assert.match(capacity, /houseCapacityRevenuePaidUnits/);
  assert.match(capacity, /earthCapacityExpensePaidUnits/);
  assert.match(capacity, /landMarginUnits/);
  assert.match(capacity, /v5_capacity_delinquency_state/);
  assert.match(capacity, /capacityRevenuePaidUnits/);
  assert.match(capacity, /treasuryUnits/);
  assert.match(capacity, /programCommitments/);
  assert.match(readiness, /resolved_constitution_snapshots_v5/);
  assert.doesNotMatch(readiness, /FROM v5_capacity_policy_versions/);
  assert.match(taxSettlement, /Canonical Earth tax snapshot is missing/);
  assert.match(routes, /\/api\/v5\/capacity/);
  assert.match(registry, /getV5EarthCapacity/);
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

test('V5 capacity settlement and quotes require resolved Constitution values', async () => {
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
  assert.match(settlement, /Canonical Earth capacity snapshot is unavailable/);
  assert.match(settlement, /Canonical Corporation capacity snapshot is unavailable/);
  assert.match(quotes, /Canonical Earth capacity snapshot is unavailable/);
  assert.doesNotMatch(settlement, /FROM v5_capacity_policy_versions/);
  assert.doesNotMatch(settlement, /FROM corporation_capacity_policy_versions/);
  assert.doesNotMatch(quotes, /FROM v5_capacity_policy_versions/);
  assert.doesNotMatch(quotes, /FROM corporation_capacity_policy_versions/);
});

test('daily tax settlement consumes the assessed-day Constitution market rate', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /resolved_constitution_snapshots_v5/);
  assert.match(settlement, /EARTH\.MARKET\.TRANSACTION_TAX_RATE/);
  assert.match(settlement, /canonicalRate\('EARTH\.TAX\.BASIC_LEVY_RATE'\)/);
  assert.match(settlement, /CORPORATION\.HOUSE_INCOME_TAX/);
  assert.match(settlement, /EARTH\.TAX\.BASIC_LEVY_RATE/);
  assert.match(settlement, /corporationMemberships/);
  assert.match(settlement, /nexus_type: 'HOUSE_INCOME'/);
});

test('House and Corporation fiscal read models expose canonical tax rules and provenance', async () => {
  const house = await readFile(new URL('../cloudflare/src/tax-statement-postgres.ts', import.meta.url), 'utf8');
  const corporation = await readFile(new URL('../cloudflare/src/corporation-fiscal-postgres.ts', import.meta.url), 'utf8');
  assert.match(house, /constitutionalTaxRules/);
  assert.match(house, /constitutionalTaxVersionIds/);
  assert.match(house, /getResolvedConstitutionForDay/);
  assert.match(corporation, /taxRulesSource/);
  assert.match(corporation, /constitution-snapshot-v5/);
  assert.match(corporation, /constitutionalTaxVersionIds/);
  const financeRoutes = await readFile(new URL('../cloudflare/src/finance-routes.ts', import.meta.url), 'utf8');
  assert.match(financeRoutes, /canonicalTaxStatement/);
  assert.match(financeRoutes, /postgres-constitutional-tax-v5/);
});

test('Corporation tax settlement selects canonical rates and rule provenance', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/corporation-tax-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /Canonical Corporation tax snapshots are unavailable/);
  assert.match(settlement, /snap\.version_ids->>'CORPORATION\.TAX\.CORPORATE_RATE'/);
  assert.match(settlement, /corporation\.tax_rule_version/);
  assert.match(settlement, /earth_post_transaction\(\$1,\$2,1439/);
  assert.doesNotMatch(settlement, /corporation-tax-v4/);
  assert.doesNotMatch(settlement, /tax_charter->>'corporateTaxBps'/);
  assert.doesNotMatch(settlement, /legacy-corporation-tax-v/);
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
  assert.match(kernel, /earthRules/);
  assert.match(kernel, /earthVersionIds/);
  assert.match(kernel, /getResolvedConstitutionForDay/);
  assert.match(kernel, /scheduledChanges/);
  assert.match(route, /governance\/v5\/constitution/);
  assert.match(route, /constitution\/preview/);
  assert.match(client, /getV5Constitution/);
});

test('V5 tax statements consume assessed-day Constitution snapshots with provenance', async () => {
  const statement = await readFile(new URL('../cloudflare/src/tax-statement-postgres.ts', import.meta.url), 'utf8');
  assert.match(statement, /getResolvedConstitutionForDay/);
  assert.match(statement, /progressive_policy_brackets/);
  assert.match(statement, /progressiveSchedules/);
  assert.match(statement, /constitutionSnapshotId/);
  assert.match(statement, /constitutionalTaxProvenance/);
});

test('V5 tax reconciliation records missing rules in both directions', async () => {
  const reconciliation = await readFile(new URL('../cloudflare/src/v5-tax-reconciliation-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/111_v5_tax_reconciliation_bidirectional.sql', import.meta.url), 'utf8');
  assert.match(reconciliation, /missingLegacy/);
  assert.match(reconciliation, /canonical:\$\{code\}/);
  assert.match(reconciliation, /legacyRateBps === null/);
  assert.match(migration, /ALTER COLUMN legacy_rate_bps DROP NOT NULL/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS missing_legacy/);
  assert.match(migration, /MISSING_LEGACY/);
});

test('V5 constitutional version ranges are protected against overlap in PostgreSQL', async () => {
  const migration = await readFile(new URL('../db/migrations/109_constitution_version_overlap_guard.sql', import.meta.url), 'utf8');
  assert.match(migration, /earth_guard_constitutional_version_overlap/);
  assert.match(migration, /existing\.effective_from_game_day <=/);
  assert.match(migration, /NEW\.effective_from_game_day <=/);
  assert.match(migration, /constitutional_rule_versions_overlap_guard/);
});

test('V5 established Constitution versions are immutable after activation', async () => {
  const migration = await readFile(new URL('../db/migrations/110_constitution_version_immutability_guard.sql', import.meta.url), 'utf8');
  assert.match(migration, /earth_guard_constitutional_version_immutability/);
  assert.match(migration, /NEW\.value_json IS DISTINCT FROM OLD\.value_json/);
  assert.match(migration, /Active constitutional rule versions may only be retired/);
  assert.match(migration, /Retired constitutional rule versions cannot be reactivated/);
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

test('legacy governance rules read path is Constitution-backed', async () => {
  const route = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  const start = route.indexOf("url.pathname === '/api/governance/rules' && request.method === 'GET'");
  const end = route.indexOf("url.pathname === '/api/governance/v4/proposals'", start);
  assert.notEqual(start, -1);
  assert.match(route.slice(start, end), /getConstitutionReadModel/);
  assert.doesNotMatch(route.slice(start, end), /FROM governance_rules/);
  assert.match(registry, /method: 'GET', path: '\/api\/governance\/rules'.*service: 'getConstitutionReadModel'/);
});

test('world governance read model uses the canonical Constitution authority', async () => {
  const world = await readFile(new URL('../cloudflare/src/world-postgres.ts', import.meta.url), 'utf8');
  const readModel = await readFile(new URL('../cloudflare/src/read-postgres.ts', import.meta.url), 'utf8');
  assert.match(world, /getConstitutionReadModel/);
  assert.match(world, /rules: constitution\.rules/);
  assert.match(world, /legacyRules: governanceRules\.rows/);
  assert.match(readModel, /listGovernanceRules[\s\S]*getConstitutionReadModel/);
  assert.doesNotMatch(readModel.slice(readModel.indexOf('export async function listGovernanceRules')), /FROM governance_rules/);
});

test('V5 Corporation fiscal read model does not expose legacy tax-rule authority', async () => {
  const fiscal = await readFile(new URL('../cloudflare/src/corporation-fiscal-postgres.ts', import.meta.url), 'utf8');
  assert.match(fiscal, /canonicalTaxSnapshotAvailable/);
  assert.match(fiscal, /unavailable-canonical-snapshot/);
  assert.match(fiscal, /getV5CorporationCapacity/);
  assert.match(fiscal, /capacitySource/);
  assert.doesNotMatch(fiscal, /SELECT r\.\* FROM tax_rule_versions/);
  assert.doesNotMatch(fiscal, /legacy-tax-rule-versions-bridge/);
});

test('V5 House tax read models use canonical constitutional rules', async () => {
  const statement = await readFile(new URL('../cloudflare/src/tax-statement-postgres.ts', import.meta.url), 'utf8');
  const finance = await readFile(new URL('../cloudflare/src/finance-routes.ts', import.meta.url), 'utf8');
  assert.match(statement, /getResolvedConstitutionForDay/);
  assert.match(statement, /generatedFrom: 'constitutional_rule_versions_v5'/);
  assert.doesNotMatch(statement, /FROM tax_rule_versions/);
  assert.match(finance, /rules: canonicalTaxStatement\?\.activeRules \?\? \[\]/);
  assert.doesNotMatch(finance, /legacy-tax-rule-versions-bridge/);
});

test('V5 House income tax settlement uses the shared progressive calculator', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /calculateProgressiveCharge/);
  assert.match(settlement, /EARTH\.HOUSE_INCOME_TAX/);
  assert.match(settlement, /CORPORATION\.HOUSE_INCOME_TAX/);
  assert.match(settlement, /baseRate: 10_000n/);
  assert.match(settlement, /v5-house-income-tax/);
  assert.doesNotMatch(settlement, /CORPORATION\.TAX\.INCOME_RATE/);
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
  const service = await readFile(new URL('../cloudflare/src/v5-governance-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /Legacy V5 policy actions are retired/);
  assert.match(service, /input\.actionType !== 'CONSTITUTION_AMENDMENT'/);
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
  assert.match(service, /allActiveCorporationsHaveCanonicalAdmissionRules/);
  assert.match(service, /CORPORATION\.ADMISSION_POLICY/);
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
  assert.match(service, /LEFT JOIN house_affiliations/);
  assert.match(service, /Public V5 construction requires an active Corporation affiliation/);
  assert.doesNotMatch(service, /Error\(['"]V5 construction requires an active Corporation affiliation/);
  assert.match(route, /\/api\/v5\/buildings/);
});

test('V5 public construction requires Corporation governance authorization', async () => {
  const service = await readFile(new URL('../cloudflare/src/v5-building-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /Public V5 construction requires Corporation governance authorization/);
  assert.match(service, /role_code IN \('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER'\)/);
  const purchaseStart = service.indexOf('export async function purchaseV5Building');
  assert.notEqual(purchaseStart, -1);
  assert.match(service.slice(purchaseStart), /requirePublicCorporationAuthorization/);
});

test('V5 civic construction dialog submits the Corporation-owned pooled path', async () => {
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  const dialogStart = buildings.indexOf('Future<void> _showCivicProposalDialog');
  const dialogEnd = buildings.indexOf('\n  @override\n  Widget build', dialogStart);
  assert.ok(dialogStart >= 0 && dialogEnd > dialogStart);
  const dialog = buildings.slice(dialogStart, dialogEnd);
  assert.match(dialog, /quoteV5Building\(buildingType\)/);
  assert.match(dialog, /quotedCreditCost/);
  assert.match(dialog, /quotedFootprint/);
  assert.doesNotMatch(dialog, /required int creditCost|required int materialCost|required int footprint/);
  assert.match(dialog, /Corporation governance authorization is required/);
  assert.match(dialog, /purchaseV5Building\(/);
  assert.doesNotMatch(dialog, /createProposal\(/);
  assert.doesNotMatch(dialog, /city council|City proposal|territorial rules/i);
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

test('V5 building research progress is read-only on the client', async () => {
  const panel = await readFile(new URL('../flutter_client/lib/features/operations/technology_panel.dart', import.meta.url), 'utf8');
  assert.doesNotMatch(panel, /_localElapsedSeconds|_calculateResearchProgress|duration_minutes.*1440/);
  assert.match(panel, /_authoritativeResearchProgress/);
  assert.match(panel, /projectProgress == null/);
});

test('V5 building research confirmation uses a server quote', async () => {
  const panel = await readFile(new URL('../flutter_client/lib/features/operations/technology_panel.dart', import.meta.url), 'utf8');
  assert.match(panel, /quoteCorporationBuildingResearch\(type\)/);
  assert.match(panel, /required Map<String, dynamic> serverQuote/);
  assert.match(panel, /quotedCost/);
  assert.match(panel, /quotedDuration/);
  const hub = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(hub, /quoteResponse\['currentBlueprint'\]/);
  assert.match(hub, /quoteResponse\['targetBlueprint'\]/);
  assert.doesNotMatch(hub, /asDoubleOr\(match\[/);
  assert.doesNotMatch(hub, /footprint \* currentTier|footprint \* targetTier/);
});

test('V5 building operations do not project progress from client time', async () => {
  const hub = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(hub, /_authoritativeBuildingProgress/);
  assert.match(hub, /_authoritativeResearchProgress/);
  assert.doesNotMatch(hub, /_localElapsedSeconds|_constructionProgressTimer|duration_minutes.*1440/);
});

test('V5 building profitability filters use settlement net credits', async () => {
  const hub = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(hub, /settlement_net_credits/);
  assert.match(hub, /netCredits != null && netCredits > 0/);
  assert.doesNotMatch(hub, /resource_output_amount.*daily_operating_credits/);
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

test('V5 Constitution client proposals use an explicit canonical effective day', async () => {
  const client = await readFile(new URL('../flutter_client/lib/core/api/earth_api_governance.dart', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../flutter_client/lib/features/command_center/dashboard.dart', import.meta.url), 'utf8');
  assert.match(client, /effectiveFromGameDay \?\? await _nextV5ConstitutionGameDay/);
  assert.match(client, /'effectiveFromGameDay': effectiveDay/);
  assert.match(dashboard, /effectiveFromGameDay:/);
});

test('V5 client finance projections consume the authoritative server ledger', async () => {
  const finance = await readFile(new URL('../flutter_client/lib/features/finance/personal_finance_panel.dart', import.meta.url), 'utf8');
  const institutions = await readFile(new URL('../flutter_client/lib/features/institutions/institutions_panels.dart', import.meta.url), 'utf8');
  assert.match(finance, /projection\['incomeUnits'\]/);
  assert.match(finance, /projection\['taxUnits'\]/);
  assert.doesNotMatch(finance, /building\['output_multiplier'\]/);
  assert.doesNotMatch(finance, /building\['cost_multiplier'\]/);
  assert.match(institutions, /building\['output_multiplier'\]/);
  assert.doesNotMatch(`${finance}\n${institutions}`, /high_output|eco_reserve|frugal/);
});

test('V5 tax amendment UI does not fabricate economic consequences', async () => {
  const dialogs = await readFile(new URL('../flutter_client/lib/features/institutions/institutions_dialogs.dart', import.meta.url), 'utf8');
  assert.doesNotMatch(dialogs, /DecisionConsequence\.municipalTaxAdjustment/);
  assert.doesNotMatch(dialogs, /oldRatePct: 5\.0/);
  assert.match(dialogs, /canonical Constitution service validates this amendment/);
});

test('V5 building UI does not fabricate settlement projections', async () => {
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(buildings, /SERVER SETTLEMENT REQUIRED/);
  assert.match(buildings, /settlement_net_/);
  assert.doesNotMatch(buildings, /addPlannerNet/);
  assert.doesNotMatch(buildings, /netYields: pNetYields/);
  assert.doesNotMatch(buildings, /building\['output_multiplier'\]/);
  assert.doesNotMatch(buildings, /building\['cost_multiplier'\]/);
  assert.doesNotMatch(buildings, /Legacy fallback if output_|Legacy fallback if input_/);
  assert.doesNotMatch(buildings, /\b8500\b|\b600\b|\b120\b/);
});

test('V5 building read model exposes latest settlement net resources', async () => {
  const world = await readFile(new URL('../cloudflare/src/world-postgres.ts', import.meta.url), 'utf8');
  for (const resource of ['credits', 'energy', 'food', 'materials', 'components', 'compute']) {
    assert.match(world, new RegExp(`settlement_net_${resource}`));
  }
  assert.match(world, /latest\.status AS latest_settlement_status/);
  assert.match(world, /FROM building_settlement_journals/);
});

test('V5 world catalog exposes authored building research economics', async () => {
  const world = await readFile(new URL('../cloudflare/src/world-postgres.ts', import.meta.url), 'utf8');
  const catalogRoute = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  const technology = await readFile(new URL('../flutter_client/lib/features/operations/technology_panel.dart', import.meta.url), 'utf8');
  assert.match(world, /c\.research_credit_units, c\.research_duration_game_days/);
  assert.match(catalogRoute, /c\.research_credit_units, c\.research_duration_game_days/);
  assert.match(technology, /bp\['research_credit_units'\]/);
  assert.match(technology, /bp\['research_duration_game_days'\]/);
});

test('V5 capacity statement replay preserves the persisted obligation status', async () => {
  const settlement = await readFile(new URL('../cloudflare/src/v5-capacity-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(settlement, /const statementDelinquency = delinquency\?\.status \?\? \(statement\.status === 'PAID' \? 'CURRENT' : 'ARREARS'\)/);
  assert.match(settlement, /statementDelinquency, baseRateResolution\.ruleSetId/);
  assert.doesNotMatch(settlement, /result === 'PAID' \? 'CURRENT' : result === 'PARTIAL' \? 'ARREARS'/);
});

test('V5 capacity statement schema accepts canonical House delinquency states', async () => {
  const migration = await readFile(new URL('../db/migrations/112_v5_capacity_statement_delinquency_status.sql', import.meta.url), 'utf8');
  const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
  assert.equal(manifest.migrationVersion, 114);
  for (const status of ['CURRENT', 'ARREARS', 'GRACE', 'EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED']) {
    assert.match(migration, new RegExp(`'${status}'`));
  }
});

test('V5 Territory containers reconcile with exact counts and monotonic sequences', async () => {
  const containers = await readFile(new URL('../cloudflare/src/v5-territory-containers-postgres.ts', import.meta.url), 'utf8');
  assert.match(containers, /const required = BigInt\(state\.required_territory_units\)/);
  assert.match(containers, /SELECT MAX\(v5_sequence_number\)/);
  assert.match(containers, /while \(BigInt\(containers\.length\) < required\)/);
  assert.match(containers, /containers\.slice\(Number\(required\)\)/);
  assert.doesNotMatch(containers, /const required = Number\(/);
});

test('V5 Corporation directory reads tax policy from Constitution versions', async () => {
  const institutions = await readFile(new URL('../cloudflare/src/institutions-postgres.ts', import.meta.url), 'utf8');
  assert.match(institutions, /constitutional_rule_versions_v5/);
  assert.match(institutions, /CORPORATION\.TAX\.INCOME_RATE/);
  assert.match(institutions, /EARTH\.CAPACITY\.BASE_RATE/);
  assert.doesNotMatch(institutions, /NULLIF\(c\.tax_charter->>'incomeTaxBps'/);
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

test('V5 historical list read models share the JSON-safe database boundary', async () => {
  const jsonSafe = await readFile(new URL('../cloudflare/src/json-safe.ts', import.meta.url), 'utf8');
  assert.match(jsonSafe, /typeof value === 'bigint'/);
  for (const file of ['v5-governance-postgres.ts', 'v5-membership-postgres.ts', 'v5-capacity-resolution-postgres.ts', 'v5-corporation-receivership-postgres.ts']) {
    const source = await readFile(new URL(`../cloudflare/src/${file}`, import.meta.url), 'utf8');
    assert.match(source, /from '\.\/json-safe\.ts'/, `${file} must use the shared JSON boundary`);
    assert.match(source, /toJsonSafe\(/, `${file} must sanitize database rows`);
  }
});

test('V5 world snapshot converts PostgreSQL bigint values at the JSON boundary', async () => {
  const world = await readFile(new URL('../cloudflare/src/world-postgres.ts', import.meta.url), 'utf8');
  assert.match(world, /PostgreSQL BIGINT values must have one explicit JSON wire representation/);
  assert.match(world, /return toJsonSafe\(\{/);
});

test('V5 Earth capacity totals include independent House direct-to-Earth obligations', async () => {
  const capacity = await readFile(new URL('../cloudflare/src/v5-capacity-postgres.ts', import.meta.url), 'utf8');
  assert.match(capacity, /capacity_level = 'CORPORATION'[\s\S]*capacity_level = 'HOUSE' AND corporation_id IS NULL/);
  assert.match(capacity, /independentUnits \+ corporationUnits \+ policy\.standardTerritoryCapacity/);
  assert.doesNotMatch(capacity, /requiredTerritoryUnits: BigInt\(corporation\?\.required_units/);
});

test('V5 upgrade review is quote-only and does not derive tier economics in Flutter', async () => {
  const dialog = await readFile(new URL('../flutter_client/lib/features/operations/building_detail_upgrade_dialog.dart', import.meta.url), 'utf8');
  assert.match(dialog, /quoteBuildingUpgrade/);
  assert.match(dialog, /server-authoritative upgrade quote/);
  assert.doesNotMatch(dialog, /getVal|dailyOperatingCredits|dailyOutputCredits|baseCreditCost|upgradeCreditCost.*asIntOr/);
});

test('V5 building catalog fails closed when authoritative construction economics are incomplete', async () => {
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(buildings, /_hasAuthoritativeCatalogEconomics/);
  assert.match(buildings, /allCatalogMaps\.removeWhere\(\(item\) => !_hasAuthoritativeCatalogEconomics/);
  assert.doesNotMatch(buildings, /item\['construction_days'\], footprint \*\s+asIntOr/);
});

test('V5 research cards do not synthesize next-tier economics', async () => {
  const technology = await readFile(new URL('../flutter_client/lib/features/operations/technology_panel.dart', import.meta.url), 'utf8');
  assert.match(technology, /_hasAuthoritativeResearchBlueprint/);
  assert.match(technology, /where\(_hasAuthoritativeResearchBlueprint\)/);
  assert.doesNotMatch(technology, /CapEx \+70% per tier/);
  assert.doesNotMatch(technology, /Output \+25% per tier/);
  assert.doesNotMatch(technology, /Slot × Tier construction days/);
});

test('V5 generic governance proposals cannot carry executable targets', async () => {
  const routes = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  assert.match(routes, /Executable governance targets are retired/);
  assert.match(routes, /status: 410/);
});

test('V5 retires territory-bound building construction mutations', async () => {
  const routes = await readFile(new URL('../cloudflare/src/real-estate-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  assert.match(routes, /Territory-bound construction is retired/);
  assert.match(routes, /use \/api\/v5\/buildings/);
  assert.match(routes, /status: 410/);
  assert.match(registry, /path: '\/api\/real-estate\/purchase'.*status: 'REMOVED'/);
  assert.match(registry, /path: '\/api\/real-estate\/quote'.*status: 'REMOVED'/);
});

test('V5 construction review quotes and executes the pooled path for independent Houses', async () => {
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/v5-building-postgres.ts', import.meta.url), 'utf8');
  const confirm = buildings.slice(buildings.indexOf('Future<void> _confirmConstruction'));
  assert.match(confirm, /quoteV5Building\(buildingType\)/);
  assert.match(confirm, /purchaseV5Building\(/);
  assert.doesNotMatch(confirm, /purchaseBuilding\(/);
  assert.match(confirm, /REPORTED AFTER GAME-DAY SETTLEMENT/);
  assert.match(service, /refreshV5SettlementProfilesForHouse\(tx, owner\.houseId/);
  assert.match(service, /rebuildV5CorporationSettlementProfile\(tx, owner\.corporationId/);
});

test('V5 building upgrades use pooled routes and null Territory project context', async () => {
  const routes = await readFile(new URL('../cloudflare/src/real-estate-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  const api = await readFile(new URL('../flutter_client/lib/core/api/earth_api_real_estate.dart', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/building-investment-postgres.ts', import.meta.url), 'utf8');
  assert.match(routes, /v5UpgradeMatch/);
  assert.match(routes, /Territory-bound building upgrades are retired/);
  assert.match(routes, /Territory-bound building upgrade quotes are retired/);
  assert.match(registry, /path: '\/api\/v5\/buildings\/\{id\}\/upgrade'.*status: 'ACTIVE'/);
  assert.match(registry, /path: '\/api\/v5\/buildings\/\{id\}\/upgrade-quote'.*status: 'ACTIVE'/);
  assert.match(registry, /path: '\/api\/real-estate\/upgrade'.*status: 'RETIRED'/);
  assert.match(registry, /path: '\/api\/real-estate\/buildings\/\{id\}\/upgrade-quote'.*status: 'RETIRED'/);
  assert.match(api, /'\/api\/v5\/buildings\/\$buildingId\/upgrade'/);
  assert.match(api, /'\/api\/v5\/buildings\/\$buildingId\/upgrade-quote'/);
  assert.match(service, /construction-investment-v5/);
  assert.match(service, /capacityModel: 'V5_POOLED'/);
  assert.match(service, /building\.owner_economic_id, null, next\.id/);
});

test('V5 Corporation building upgrades use Corporation governance and Treasury', async () => {
  const service = await readFile(new URL('../cloudflare/src/building-investment-postgres.ts', import.meta.url), 'utf8');
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.match(service, /owner\.owner_type = 'CORPORATION'/);
  assert.match(service, /quoteV5CorporationCapacityChange/);
  assert.match(service, /account_type = 'TREASURY'/);
  assert.match(service, /Corporation governance authorization is required/);
  assert.match(service, /rebuildV5CorporationSettlementProfile/);
  assert.match(buildings, /quoteBuildingUpgrade\(buildingId: buildingId!/);
  assert.match(buildings, /upgradeBuilding\(buildingId: buildingId!/);
});

test('V5 Corporation building policies use Corporation governance', async () => {
  const service = await readFile(new URL('../cloudflare/src/building-investment-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /setCorporationBuildingOperatingMode/);
  assert.match(service, /quoteCorporationBuildingOperatingMode/);
  assert.match(service, /BUILDING_OPERATING_POLICY_CHANGED/);
  assert.match(service, /ownerType: 'CORPORATION', currentMode: building\.operating_mode/);
});

test('V5 Corporation capital projects use Corporation Treasury and pooled settlement', async () => {
  const service = await readFile(new URL('../cloudflare/src/building-age-postgres.ts', import.meta.url), 'utf8');
  assert.match(service, /startCorporationCapitalProject/);
  assert.match(service, /owner\.owner_type = 'CORPORATION'/);
  assert.match(service, /account_type = 'TREASURY'/);
  assert.match(service, /rebuildV5CorporationSettlementProfile/);
  assert.match(service, /ownerType: 'CORPORATION'/);
  assert.match(service, /territoryPlacement: null/);
});

test('V5 building lifecycle routes cover policy, demolition, and capital actions', async () => {
  const routes = await readFile(new URL('../cloudflare/src/real-estate-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  const api = await readFile(new URL('../flutter_client/lib/core/api/earth_api_real_estate.dart', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/building-age-postgres.ts', import.meta.url), 'utf8');
  for (const marker of ['v5PolicyMatch', 'v5PolicyQuoteMatch', 'v5DemolishMatch', 'v5DemolitionQuoteMatch', 'v5CapitalOptionsMatch', 'v5CapitalProjectMatch']) {
    assert.match(routes, new RegExp(marker));
  }
  for (const path of [
    '/api/v5/buildings/{id}/policy',
    '/api/v5/buildings/{id}/policy-quote',
    '/api/v5/buildings/{id}/demolish',
    '/api/v5/buildings/{id}/demolition-quote',
    '/api/v5/buildings/{id}/capital-options',
    '/api/v5/buildings/{id}/capital-projects',
  ]) assert.match(registry, new RegExp(path.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&') + ".*status: 'ACTIVE'"));
  assert.match(api, /\/api\/v5\/buildings\/\$buildingId\/policy/);
  assert.match(api, /\/api\/v5\/buildings\/\$buildingId\/demolish/);
  assert.match(api, /\/api\/v5\/buildings\/\$buildingId\/capital-projects/);
  assert.match(service, /capital-project-v5/);
  assert.match(service, /refreshV5SettlementProfilesForHouse\(tx, building\.house_id/);
  assert.match(service, /VALUES \(\$1,\$2,\$3,NULL/);
});

test('V5 Corporation client mutations do not fall back to Territory-bound endpoints', async () => {
  const api = await readFile(new URL('../flutter_client/lib/core/api/earth_api_institutions.dart', import.meta.url), 'utf8');
  const joinStart = api.indexOf('Future<EarthState> joinCorporation');
  const createStart = api.indexOf('Future<EarthState> createCorporation');
  assert.ok(joinStart >= 0 && createStart > joinStart);
  const joinSlice = api.slice(joinStart, createStart);
  const createSlice = api.slice(createStart, api.indexOf('Future<EarthState> spendCorporationTreasury'));
  assert.match(joinSlice, /api\/v5\/corporations/);
  assert.doesNotMatch(joinSlice, /api\/corporations\/\$corporationId\/membership/);
  assert.match(createSlice, /api\/v5\/corporations/);
  assert.doesNotMatch(createSlice, /'territoryName'/);
});

test('Legacy Corporation mutation endpoints are retired after V5 cutover', async () => {
  const routes = await readFile(new URL('../cloudflare/src/institutions-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  assert.match(routes, /Legacy Corporation founding is retired/);
  assert.match(routes, /Legacy Corporation membership is retired/);
  assert.match(registry, /path: '\/api\/corporations'.*status: 'RETIRED'/);
  assert.match(registry, /path: '\/api\/corporations\/\{id\}\/membership'.*status: 'RETIRED'/);
});

test('V5 House UI and routes do not offer Territory-specific residence changes', async () => {
  const routes = await readFile(new URL('../cloudflare/src/house-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  const panel = await readFile(new URL('../flutter_client/lib/features/institutions/territory_commons_panel.dart', import.meta.url), 'utf8');
  const renderedPanel = panel.slice(panel.indexOf('  @override\n  Widget build'));
  assert.match(routes, /Territory-specific residence moves are retired in V5/);
  assert.match(registry, /path: '\/api\/house\/residency\/move'.*status: 'RETIRED'/);
  assert.doesNotMatch(renderedPanel, /ACQUIRE USE RIGHT|RELOCATE RESIDENCE|RELEASE USE RIGHT/);
});

test('V5 retires Territory use-right mutation endpoints while preserving history reads', async () => {
  const routes = await readFile(new URL('../cloudflare/src/real-estate-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  assert.match(routes, /Territory use-right acquisition is retired in V5/);
  assert.match(routes, /Territory use-right release is retired in V5/);
  assert.match(registry, /path: '\/api\/real-estate\/rights'.*status: 'RETIRED'/);
  assert.match(registry, /path: '\/api\/real-estate\/rights\/\{id\}\/release'.*status: 'RETIRED'/);
  assert.match(registry, /path: '\/api\/real-estate\/rights'.*service: 'listTerritoryRights'.*status: 'ACTIVE'/);
});

test('V5 operations UI has no dead legacy real-estate dialog path', async () => {
  const buildings = await readFile(new URL('../flutter_client/lib/features/operations/buildings_hub_screen.dart', import.meta.url), 'utf8');
  assert.doesNotMatch(buildings, /real_estate_dialogs\.dart/);
  await assert.rejects(
    readFile(new URL('../flutter_client/lib/features/operations/real_estate_dialogs.dart', import.meta.url)),
    /ENOENT/,
  );
});

test('V5 Daily Briefing does not replace unavailable data with zero settlement values', async () => {
  const summary = await readFile(new URL('../flutter_client/lib/features/command_center/executive_command_summary.dart', import.meta.url), 'utf8');
  assert.match(summary, /_briefing = null/);
  assert.match(summary, /empty report would look like a real zero-valued settlement/);
  assert.doesNotMatch(summary, /_briefing = DailySummaryReport\.empty/);
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
