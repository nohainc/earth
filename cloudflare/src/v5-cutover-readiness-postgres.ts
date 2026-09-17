import type { PostgresRepository } from './repository.ts';
import { EARTH_SCHEMA_VERSION } from './schema-contract.ts';

type ReadinessRow = { count: string };

/**
 * Read-only cutover gate. It never enables a feature or mutates gameplay; it
 * produces the evidence required before an operator may enable V5 posting.
 */
export async function getV5CutoverReadiness(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const world = (await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'"))
    .rows[0];
  const gameDay = Number(world?.game_day ?? 0);
  const [migration, earthPolicy, corporationCoverage, admissionCoverage, backfill, missingCapacity, failedRuns, earthSnapshot, corporationSnapshots, definitions, taxReconciliation] = await Promise.all([
    repository.query<ReadinessRow>('SELECT COALESCE(MAX(version), 0)::TEXT AS count FROM earth_schema_migrations'),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM resolved_constitution_snapshots_v5
     WHERE authority_type = 'EARTH' AND authority_id = 'EARTH' AND game_day = $1
       AND rules_json ? 'EARTH.CAPACITY.STANDARD'
       AND rules_json ? 'EARTH.CAPACITY.BASE_RATE'
       AND rules_json ? 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE'
       AND rules_json ? 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE'`, [gameDay]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM corporations c
     WHERE c.status = 'ACTIVE'
       AND EXISTS (SELECT 1 FROM resolved_constitution_snapshots_v5 s
                    WHERE s.authority_type = 'CORPORATION' AND s.authority_id = c.id AND s.game_day = $1
                      AND s.rules_json ? 'CORPORATION.HOUSE_CAPACITY.BASE_RATE')`, [gameDay]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM corporations c
     WHERE c.status = 'ACTIVE'
       AND EXISTS (SELECT 1 FROM constitutional_rule_versions_v5 v
                    WHERE v.rule_code = 'CORPORATION.ADMISSION_POLICY'
                      AND v.authority_type = 'CORPORATION'
                      AND v.authority_id = c.id
                      AND v.status IN ('ACTIVE', 'RETIRED')
                      AND v.effective_from_game_day <= $1
                      AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= $1))`, [gameDay]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM v5_capacity_backfill_runs WHERE status = 'COMPLETED'`),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM corporations c
     WHERE c.status = 'ACTIVE'
       AND NOT EXISTS (SELECT 1 FROM corporation_capacity_state_v5 s
                        WHERE s.corporation_id = c.id AND s.game_day = $1)`, [Math.max(1, gameDay - 1)]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM daily_settlement_runs WHERE status = 'failed' AND game_day >= $1`, [Math.max(1, gameDay - 2)]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM resolved_constitution_snapshots_v5
     WHERE authority_type = 'EARTH' AND authority_id = 'EARTH' AND game_day = $1`, [Math.max(1, gameDay - 1)]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM corporations c
     WHERE c.status = 'ACTIVE'
       AND EXISTS (SELECT 1 FROM resolved_constitution_snapshots_v5 s
                    WHERE s.authority_type = 'CORPORATION' AND s.authority_id = c.id AND s.game_day = $1)`, [Math.max(1, gameDay - 1)]),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM constitutional_rule_definitions_v5 WHERE active = TRUE`),
    repository.query<ReadinessRow>(`SELECT COUNT(*)::TEXT AS count
      FROM v5_tax_reconciliation_runs
     WHERE assessed_game_day = $1 AND status = 'COMPLETED'
       AND mismatches = 0 AND missing_canonical = 0 AND missing_legacy = 0`, [Math.max(1, gameDay - 1)]),
  ]);
  const activeCorporations = Number((await repository.query<ReadinessRow>(
    "SELECT COUNT(*)::TEXT AS count FROM corporations WHERE status = 'ACTIVE'",
  )).rows[0]?.count ?? 0);
  const checks = {
    schemaVersionMatches: Number(migration.rows[0]?.count ?? 0) === EARTH_SCHEMA_VERSION,
    activeEarthPolicy: Number(earthPolicy.rows[0]?.count ?? 0) === 1,
    allActiveCorporationsHavePolicy: Number(corporationCoverage.rows[0]?.count ?? 0) === activeCorporations,
    allActiveCorporationsHaveCanonicalAdmissionRules: Number(admissionCoverage.rows[0]?.count ?? 0) === activeCorporations,
    capacityBackfillCompleted: Number(backfill.rows[0]?.count ?? 0) > 0,
    allActiveCorporationsHaveCapacityState: Number(missingCapacity.rows[0]?.count ?? 0) === 0,
    earthConstitutionSnapshotAvailable: Number(earthSnapshot.rows[0]?.count ?? 0) === 1,
    allActiveCorporationsHaveConstitutionSnapshot: Number(corporationSnapshots.rows[0]?.count ?? 0) === activeCorporations,
    constitutionalDefinitionsPresent: Number(definitions.rows[0]?.count ?? 0) > 0,
    taxReconciliationClean: Number(taxReconciliation.rows[0]?.count ?? 0) === 1,
    noRecentFailedSettlementRuns: Number(failedRuns.rows[0]?.count ?? 0) === 0,
    shadowOnlyUntilExplicitEnablement: true,
  };
  const eligible = Object.values(checks).every(Boolean);
  return {
    ok: true,
    eligible,
    gameDay,
    checks,
    evidence: {
      actualSchemaVersion: Number(migration.rows[0]?.count ?? 0),
      expectedSchemaVersion: EARTH_SCHEMA_VERSION,
      activeCorporations,
      activeCorporationPolicies: Number(corporationCoverage.rows[0]?.count ?? 0),
      activeCorporationAdmissionRules: Number(admissionCoverage.rows[0]?.count ?? 0),
      completedBackfills: Number(backfill.rows[0]?.count ?? 0),
      missingCorporationCapacityStates: Number(missingCapacity.rows[0]?.count ?? 0),
      recentFailedSettlementRuns: Number(failedRuns.rows[0]?.count ?? 0),
      earthConstitutionSnapshots: Number(earthSnapshot.rows[0]?.count ?? 0),
      corporationConstitutionSnapshots: Number(corporationSnapshots.rows[0]?.count ?? 0),
      constitutionalDefinitions: Number(definitions.rows[0]?.count ?? 0),
      cleanTaxReconciliationRuns: Number(taxReconciliation.rows[0]?.count ?? 0),
    },
    generatedFrom: 'postgres-canonical-facts-v5',
    mutationEnabled: false,
  };
}
