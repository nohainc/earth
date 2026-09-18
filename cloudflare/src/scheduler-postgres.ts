import type { PostgresRepository } from './repository.ts';
import type { FeatureConfig } from './feature-config.ts';
import { createDailySettlementPhaseRegistry, type DailySettlementPhaseContext } from './daily-settlement-phases.ts';
import { settleCorporationDynamics, settleTerritoryCapacityProjections } from './territory-settlement-postgres.ts';
import { settleBuildingUpkeepAndRevenueV2 } from './building-settlement-v2.ts';
import { settleLifeMaintenanceInTransaction } from './life-maintenance-postgres.ts';
import { activatePendingHouseSuccessors, processHouseMortality } from './lifecycle-postgres.ts';
import { refreshResourceAnalyticsInTransaction } from './resource-analytics-postgres.ts';
import { refreshHouseDailyStatementsInTransaction } from './house-daily-summary-postgres.ts';
import { settleHouseNeedsAndServices } from './service-settlement-postgres.ts';
import { claimSettlementWork, completeSettlementWork, ensureSettlementWork, failSettlementWork, settlementWorkProgress } from './settlement-work-postgres.ts';
import { executeHousePoliciesForDay } from './house-policy-execution.ts';
import { settlePerishableResourceDecay } from './resource-settlement-postgres.ts';
import { completeDueConstructionProjects } from './construction-settlement-postgres.ts';
import { advanceGlobalPrograms } from './global-programs-postgres.ts';
import { advanceTechnologyGenerationPrograms } from './technology-generations-postgres.ts';
import { advanceV5ResearchProjects } from './technology-postgres.ts';
import { settleBankLoanRisk } from './banking-postgres.ts';
import { refreshOrganizationFinancialStates } from './organization-stress-postgres.ts';
import { executeDueOrganizationResolutions } from './organization-stress-postgres.ts';
import { settleDuePublicProjectsInTransaction } from './public-projects-postgres.ts';
import { refreshRankingSnapshots } from './rankings-postgres.ts';
import { settleTerritoryLeases } from './territory-rights-postgres.ts';
import { settleCommonsDividends } from './commons-dividends-postgres.ts';
import { settlePublicTaxesInTransaction } from './tax-settlement-postgres.ts';
import { refreshInstitutionFinancialSnapshots } from './institution-financial-settlement-postgres.ts';
import { refreshPostSuccessionAccess } from './post-succession-access-postgres.ts';
import { settlePatentExpirations } from './patent-settlement-postgres.ts';
import { settleTechnologyLicenseFees } from './ip-license-settlement-postgres.ts';
import { settleGlobalBank } from './global-bank-settlement-engine.ts';
import { settleCorporationIncomeTax } from './corporation-tax-settlement-postgres.ts';
import { settleV5CapacityInTransaction } from './v5-capacity-settlement-postgres.ts';
import { reconcileV5TerritoryContainersInTransaction } from './v5-territory-containers-postgres.ts';
import { activateDueV5GovernancePoliciesInTransaction } from './v5-governance-postgres.ts';
import { rebuildV5SettlementProfilesInShard, settleV5CorporationSettlementProfiles } from './v5-settlement-profiles-postgres.ts';
import { materializeResolvedConstitutionSnapshot } from './constitutional-kernel-postgres.ts';
import { reconcileV5TaxRulesInTransaction } from './v5-tax-reconciliation-postgres.ts';
import { captureEconomyShadowOpening, reconcileEconomyShadowDay } from './economy-shadow.ts';
import { marketBatchThroughClosedDay, processDueMarketBatches } from './market-scheduler.ts';

// Settlement claiming is delegated to the database lease function
// earth_claim_settlement_day so concurrent schedulers cannot double-claim work.
// Failures are recorded through earth_fail_settlement_day and are retryable
// until the database attempt ceiling is reached.

export type SettlementResult = { status: 'completed' | 'already_processed' | 'busy' | 'failed'; gameDay: number; phasesCompleted: number; workUnitsCompleted?: number; workUnitsPending?: number };

const noOpPhase = async (_context: DailySettlementPhaseContext): Promise<unknown> => ({ ok: true });
const OWNER_SHARD_COUNT = 16;
const settlementPhases = createDailySettlementPhaseRegistry({
  v5PolicyActivation: async ({ tx, day }) => activateDueV5GovernancePoliciesInTransaction(tx, day),
  constitutionSnapshots: async ({ tx, day }) => {
    await materializeResolvedConstitutionSnapshot(tx, { authorityType: 'EARTH', authorityId: 'EARTH', gameDay: day });
    const corporations = (await tx.query<{ id: string }>("SELECT id FROM corporations WHERE status = 'ACTIVE' ORDER BY id")).rows;
    for (const corporation of corporations) await materializeResolvedConstitutionSnapshot(tx, { authorityType: 'CORPORATION', authorityId: corporation.id, gameDay: day });
    return { earth: 1, corporations: corporations.length };
  },
  activateSuccessors: async ({ tx, day }) => ({ activated: await activatePendingHouseSuccessors(tx, day) }),
  preparePartitions: noOpPhase,
  rebuildProfiles: async ({ tx, day, shard, shardCount }) => rebuildV5SettlementProfilesInShard(tx, day, shard ?? 0, shardCount ?? OWNER_SHARD_COUNT),
  profileSettlement: async ({ tx, day }) => settleV5CorporationSettlementProfiles(tx, day),
  lifeMaintenance: async ({ tx, day }) => settleLifeMaintenanceInTransaction(tx, day),
  basicLevy: noOpPhase,
  ipLicenseBilling: async ({ tx, day }) => settleTechnologyLicenseFees(tx, day),
  buildingSettlement: async ({ tx, day, shard, shardCount }) => settleBuildingUpkeepAndRevenueV2(tx, day, { shard, shardCount }),
  corporationIncomeTax: async ({ tx, day }) => settleCorporationIncomeTax(tx, day),
  publicTaxAssessment: async ({ tx, day, shard, shardCount }) => settlePublicTaxesInTransaction(tx, day, shard, shardCount),
  taxReconciliation: async ({ tx, day }) => reconcileV5TaxRulesInTransaction(tx, day),
  globalBank: async ({ tx, day }) => ({ settled: await settleGlobalBank(tx, day) }),
  bankHealth: async ({ tx, day }) => settleBankLoanRisk(tx, day),
  mandatoryBudgetPayments: noOpPhase,
  scheduledBudgetPayments: noOpPhase,
  territoryCapacityProjections: async ({ tx, day }) => settleTerritoryCapacityProjections(tx, day),
  v5Capacity: async ({ tx, day }) => settleV5CapacityInTransaction(tx, day),
  v5TerritoryContainers: async ({ tx, day }) => reconcileV5TerritoryContainersInTransaction(tx, day - 1),
  corporationDynamics: async ({ tx, day }) => settleCorporationDynamics(tx, day),
  houseNeedsServices: async ({ tx, day, shard, shardCount }) => settleHouseNeedsAndServices(tx, day, shard, shardCount),
  perishableResourceDecay: async ({ tx, day, shard, shardCount }) => settlePerishableResourceDecay(tx, day, shard, shardCount),
  constructionCompletion: async ({ tx, day, shard, shardCount }) => completeDueConstructionProjects(tx, day, shard, shardCount),
  territoryLeaseSettlement: async ({ tx, day, shard, shardCount }) => settleTerritoryLeases(tx, day, shard, shardCount),
  commonsDividendSettlement: async ({ tx, day }) => settleCommonsDividends(tx, day),
  budgetDividendEligibility: noOpPhase,
  patentExpirations: async ({ tx, day }) => settlePatentExpirations(tx, day),
  researchAndProgress: async ({ tx, day }) => ({
    legacy: await advanceTechnologyGenerationPrograms(tx, day),
    v5: await advanceV5ResearchProjects(tx, day),
  }),
  globalPrograms: async ({ tx, day }) => advanceGlobalPrograms(tx, day),
  publicProjects: async ({ tx, day }) => settleDuePublicProjectsInTransaction(tx, day),
  housePolicyExecution: async ({ tx, day, shard, shardCount }) => executeHousePoliciesForDay(tx, day, { shard, shardCount }),
  lifecycle: async ({ tx, day }) => processHouseMortality(tx, day),
  postSuccessionAccessRefresh: async ({ tx, day }) => refreshPostSuccessionAccess(tx, day),
  financialStates: async ({ tx, day }) => refreshOrganizationFinancialStates(tx, day),
  institutionDissolution: async ({ tx, day }) => executeDueOrganizationResolutions(tx, day),
  financialProjections: async ({ tx, day }) => refreshInstitutionFinancialSnapshots(tx, day),
  rankingsSnapshot: async ({ tx, day }) => refreshRankingSnapshots(tx, day),
  endOfDaySnapshots: async ({ tx, day }) => {
    await refreshResourceAnalyticsInTransaction(tx, day);
    return refreshHouseDailyStatementsInTransaction(tx, day);
  },
});

export async function runResumableSettlementDay(repository: PostgresRepository, gameDay: number, options: { workBudgetMs?: number; workerId?: string; maxWorkUnits?: number } = {}): Promise<SettlementResult> {
  const correlationId = `settlement:${gameDay}`;
  const existing = await repository.query<{ status: string }>('SELECT status FROM daily_settlement_runs WHERE game_day = $1', [gameDay]);
  if (existing.rows[0]?.status === 'completed') return { status: 'already_processed', gameDay, phasesCompleted: settlementPhases.filter((phase) => phase.status === 'required').length, workUnitsCompleted: 0, workUnitsPending: 0 };
  await captureEconomyShadowOpening(repository, gameDay);
  await repository.transaction(async (tx) => {
    await tx.query(`INSERT INTO daily_settlement_runs (game_day, status, current_phase, started_at) VALUES ($1, 'running', $2, CURRENT_TIMESTAMP) ON CONFLICT (game_day) DO UPDATE SET status = CASE WHEN daily_settlement_runs.status = 'failed' THEN 'running' ELSE daily_settlement_runs.status END, updated_at = CURRENT_TIMESTAMP`, [gameDay, settlementPhases[0]?.id ?? 'settlement']);
    await ensureSettlementWork(tx, gameDay, settlementPhases, OWNER_SHARD_COUNT);
  });
  const startedAt = Date.now();
  const workerId = options.workerId ?? `worker:${crypto.randomUUID()}`;
  const requiredPhases = settlementPhases.filter((phase) => phase.status === 'required');
  const maxWorkUnits = options.maxWorkUnits ?? Number.POSITIVE_INFINITY;
  let completed = 0;
  while (completed < maxWorkUnits && Date.now() - startedAt < (options.workBudgetMs ?? 20_000)) {
    const work = await repository.transaction((tx) => claimSettlementWork(tx, gameDay, workerId));
    if (!work) break;
    const phase = settlementPhases.find((candidate) => candidate.id === work.phase_id);
    if (!phase) throw new Error(`Settlement phase is not registered: ${work.phase_id}`);
    try {
      await repository.transaction(async (tx) => {
        const heartbeat = await tx.query<{ heartbeat: boolean }>('SELECT earth_heartbeat_settlement_day($1, $2, $3) AS heartbeat', [gameDay, workerId, phase.id]);
        if (!heartbeat.rows[0]?.heartbeat) throw new Error('Settlement day lease lost');
        await phase.execute({ tx, day: gameDay, ...(phase.shardMode === 'owner-shards' ? { shard: work.shard, shardCount: OWNER_SHARD_COUNT } : {}) });
        await completeSettlementWork(tx, work.id, workerId);
        await tx.query('INSERT INTO scheduler_runs (game_day, phase, status, correlation_id, completed_at) VALUES ($1, $2, \'completed\', $3, CURRENT_TIMESTAMP) ON CONFLICT (correlation_id) DO NOTHING', [gameDay, phase.id, `${correlationId}:${phase.id}:${work.shard}`]);
      });
      completed += 1;
    } catch (error) {
      await repository.transaction((tx) => failSettlementWork(tx, work.id, workerId, error));
      if (work.attempt_count >= 5) return { status: 'failed', gameDay, phasesCompleted: 0, workUnitsCompleted: completed, workUnitsPending: 1 };
    }
  }
  const progress = await settlementWorkProgress(repository, gameDay);
  if (progress.failed > 0) return { status: 'failed', gameDay, phasesCompleted: 0, workUnitsCompleted: completed, workUnitsPending: progress.pending };
  if (progress.pending > 0) return { status: 'busy', gameDay, phasesCompleted: 0, workUnitsCompleted: completed, workUnitsPending: progress.pending };
  try {
    await reconcileEconomyShadowDay(repository, gameDay);
    await repository.query('SELECT earth_finalize_settlement_day($1)', [gameDay]);
  } catch (error) {
    await repository.query(
      `UPDATE daily_settlement_runs
          SET status = 'failed', error_message = $2, updated_at = CURRENT_TIMESTAMP
        WHERE game_day = $1 AND status = 'running'`,
      [gameDay, error instanceof Error ? error.message.slice(0, 1000) : String(error).slice(0, 1000)],
    ).catch(() => {});
    return { status: 'failed', gameDay, phasesCompleted: 0, workUnitsCompleted: completed, workUnitsPending: 0 };
  }
  return { status: 'completed', gameDay, phasesCompleted: requiredPhases.length, workUnitsCompleted: completed, workUnitsPending: 0 };
}

import { readAuthoritativeGameTime, getSettlementCursor, lastClosedGameDay } from './world-clock-postgres.ts';

export async function runWorldSchedulerTick(
  repository: PostgresRepository,
  idempotencyKey = crypto.randomUUID(),
  _features?: FeatureConfig,
  schedulerRunId?: string,
  options: { workBudgetMs?: number; maxCatchupDays?: number } = {},
): Promise<{
  day: number;
  minute: number;
  newDay: boolean;
  settledGameDay?: number;
  settlementStatus: SettlementResult['status'];
  productionEvents: number;
  marketSettlements: number;
  marketProcessedThroughBatch?: number;
  marketEligibleBatch?: number;
  policyActions?: number;
  policyExceptions?: number;
  alreadyProcessed?: boolean;
  settledDays: number;
  backlogDays: number;
}> {
  // 1. Authoritative game clock is derived from real-world time (genesis_at).
  // Time advances continuously regardless of scheduler executions.
  const clock = await readAuthoritativeGameTime(repository);
  const targetDay = lastClosedGameDay(clock); // Never settle the open game day
  const cursor = await getSettlementCursor(repository, clock.gameDay);

  const workBudgetMs = options.workBudgetMs ?? 20_000;
  const maxCatchupDays = options.maxCatchupDays ?? 3;
  const startedAt = Date.now();

  let currentSettled = cursor.settledThroughGameDay;
  let settledDays = 0;
  let lastStatus: SettlementResult['status'] = currentSettled >= targetDay ? 'already_processed' : 'completed';
  let marketSettlements = 0;
  let lastMarket: Awaited<ReturnType<typeof processDueMarketBatches>> | null = null;

  // 2. Strict sequential catch-up for all uncompleted closed days (single orchestrator).
  // Each day's market interval is drained before that day is settled. This
  // preserves the same causal order after a scheduler outage as during normal
  // continuous execution, while keeping the market watermark independent.
  while (currentSettled < targetDay && settledDays < maxCatchupDays && Date.now() - startedAt < workBudgetMs) {
    const nextDay = currentSettled + 1;
    const workerId = `scheduler:${idempotencyKey}:${nextDay}`;
    const remainingBudget = Math.max(1000, workBudgetMs - (Date.now() - startedAt));
    const marketBudget = Math.max(1000, Math.floor(remainingBudget / 2));
    const marketTargetBatch = marketBatchThroughClosedDay(nextDay);
    const marketBeforeSettlement = await processDueMarketBatches(
      repository,
      marketBudget,
      `${workerId}:market`,
      _features,
      nextDay,
    );
    lastMarket = marketBeforeSettlement;
    marketSettlements += marketBeforeSettlement.batchesProcessed;
    if (marketBeforeSettlement.processedThroughMarketBatch < marketTargetBatch) {
      lastStatus = 'busy';
      break;
    }

    const settlementBudget = Math.max(1000, workBudgetMs - (Date.now() - startedAt));
    const settlement = await runResumableSettlementDay(repository, nextDay, { workerId, workBudgetMs: settlementBudget });

    lastStatus = settlement.status;

    if (settlement.status !== 'completed' && settlement.status !== 'already_processed') {
      // Must halt immediately on failure or busy state. Never skip a failed day.
      break;
    }

    if (settlement.status === 'completed') {
      settledDays += 1;
    }
    currentSettled = nextDay;
  }

  let totalPolicyActions = 0;
  let totalPolicyExceptions = 0;
  if (currentSettled > cursor.settledThroughGameDay) {
    const policySummary = await repository.query<{ actions: string; exceptions: string }>(
      `SELECT COUNT(*) FILTER (WHERE action_type <> 'EXCEPTION')::TEXT AS actions,
              COUNT(*) FILTER (WHERE action_type = 'EXCEPTION')::TEXT AS exceptions
         FROM policy_execution_log
        WHERE game_day > $1 AND game_day <= $2`,
      [cursor.settledThroughGameDay, currentSettled],
    ).catch(() => ({ rows: [] }));
    totalPolicyActions = Number(policySummary.rows[0]?.actions ?? 0);
    totalPolicyExceptions = Number(policySummary.rows[0]?.exceptions ?? 0);
  }

  // Once all closed days are settled, market processing may catch up through
  // the currently eligible partial open-day batches. If settlement is still
  // behind, do not move the market beyond the last settled day.
  const finalMarket = await processDueMarketBatches(
    repository,
    Math.max(1000, (options.workBudgetMs ?? 20_000) / 2),
    `scheduler:${idempotencyKey}:market-final`,
    _features,
    currentSettled >= targetDay ? undefined : currentSettled,
  );
  lastMarket = finalMarket;
  marketSettlements += finalMarket.batchesProcessed;

  if (schedulerRunId) {
    await repository.query(
      "UPDATE scheduler_runs SET completed_at = CURRENT_TIMESTAMP, status = 'completed', game_day = $2, phase = 'daily_economy' WHERE id = $1",
      [schedulerRunId, clock.gameDay],
    ).catch(() => {});
  }

  const backlogDays = Math.max(0, targetDay - currentSettled);

  return {
    day: clock.gameDay,
    minute: clock.gameMinute,
    newDay: false,
    settledGameDay: currentSettled,
    settlementStatus: lastStatus,
    productionEvents: 0,
    marketSettlements,
    marketProcessedThroughBatch: lastMarket?.processedThroughMarketBatch,
    marketEligibleBatch: lastMarket?.eligibleMarketBatch,
    policyActions: totalPolicyActions,
    policyExceptions: totalPolicyExceptions,
    alreadyProcessed: cursor.settledThroughGameDay >= targetDay,
    settledDays,
    backlogDays,
  };
}
