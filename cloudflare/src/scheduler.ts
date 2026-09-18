import type { PostgresRepository } from './repository.ts';
import { runWorldSchedulerTick } from './scheduler-postgres.ts';
import { featureConfig, type FeatureConfig } from './feature-config.ts';

export type SchedulerHeartbeatResult = {
  schedulerRunId: string;
  day: number;
  minute: number;
  safeProcessedGameDay: number;
  settlementWatermark: number;
  settlementBacklog: number;
  settledDays: number;
  settlementStatus?: string;
  marketSettlements: number;
};

export type SchedulerHeartbeatOptions = {
  maxCatchupDays?: number;
  workBudgetMs?: number;
  minutesPerTick?: number;
  features?: FeatureConfig;
};

function positiveInteger(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

import { readAuthoritativeGameTime, getSettlementCursor } from './world-clock-postgres.ts';

async function readSettlementPosition(repository: PostgresRepository): Promise<{ day: number; watermark: number }> {
  const clock = await readAuthoritativeGameTime(repository);
  const cursor = await getSettlementCursor(repository, clock.gameDay);
  return {
    day: clock.gameDay,
    watermark: cursor.settledThroughGameDay,
  };
}

/**
 * Cron is only a wake-up signal. The database clock and contiguous settlement
 * watermark determine what work is safe to process.
 *
 * Work classes:
 * - Daily: settlement days, processed strictly in watermark order.
 * - Timed: due scheduled actions, processed after the safe day.
 * - Batch: market clearing, processed only when caught up to the safe day.
 * - Derived: world indexes, refreshed by the world scheduler tick.
 * - Annual: lifecycle work, triggered by the relevant settled day.
 */
export async function runSchedulerHeartbeat(
  repository: PostgresRepository,
  scheduledTime: string | number,
  options: SchedulerHeartbeatOptions = {},
): Promise<SchedulerHeartbeatResult> {
  const startedAt = Date.now();
  const maxCatchupDays = positiveInteger(options.maxCatchupDays ?? 3, 3);
  const workBudgetMs = positiveInteger(options.workBudgetMs ?? 20_000, 20_000);
  const minutesPerTick = positiveInteger(options.minutesPerTick ?? 60, 60);
  const features = options.features ?? featureConfig(undefined);
  const before = await readSettlementPosition(repository);
  const correlationId = `cron:${String(scheduledTime)}`;
  const prior = await repository.query<{ id: string; status: string }>('SELECT id, status FROM scheduler_runs WHERE correlation_id = $1', [correlationId]);
  if (prior.rows[0]?.status === 'completed') {
    const current = await readSettlementPosition(repository);
    return { schedulerRunId: prior.rows[0].id, day: current.day, minute: 0, safeProcessedGameDay: current.watermark, settlementWatermark: current.watermark, settlementBacklog: Math.max(0, current.day - 1 - current.watermark), settledDays: 0, settlementStatus: 'already_processed', marketSettlements: 0 };
  }
  const run = await repository.query<{ id: string }>(
    `INSERT INTO scheduler_runs (game_day, phase, status, correlation_id)
     VALUES ($1,'daily_economy','running',$2)
     ON CONFLICT (correlation_id) DO UPDATE SET status = scheduler_runs.status
     RETURNING id`,
    [before.day, correlationId],
  );
  const runId = run.rows[0]?.id;
  let settledDays = 0;
  let actionsProcessed = 0;
  let lastTick: Awaited<ReturnType<typeof runWorldSchedulerTick>>;
  try {
    lastTick = await runWorldSchedulerTick(repository, String(scheduledTime), features, minutesPerTick, runId);
    if (lastTick.settlementStatus === 'completed') settledDays += 1;
    let position = await readSettlementPosition(repository);
    while (position.watermark < position.day - 1 && settledDays < maxCatchupDays && Date.now() - startedAt < workBudgetMs) {
      const nextDay = position.watermark + 1;
      lastTick = await runWorldSchedulerTick(repository, `${scheduledTime}:catchup:${nextDay}`, features, minutesPerTick);
      if (lastTick.settlementStatus === 'busy' || lastTick.settlementStatus === 'failed') break;
      if (lastTick.settlementStatus === 'completed') settledDays += 1;
      const nextPosition = await readSettlementPosition(repository);
      if (nextPosition.watermark <= position.watermark) break;
      position = nextPosition;
    }
    position = await readSettlementPosition(repository);
    // Baseline 001 contains no legacy scheduled-action or market settlement
    // projections. Those phases activate once their canonical tables exist.
    // The daily settlement watermark itself is the authoritative heartbeat.
    const market = { batchesProcessed: 0, tradesCreated: 0, busy: false };
    const after = await readSettlementPosition(repository);
    const status = lastTick.settlementStatus === 'busy' ? 'busy' : lastTick.settlementStatus === 'failed' ? 'failed' : after.watermark < after.day - 1 ? 'partial' : 'completed';
    await repository.query(
      `UPDATE scheduler_runs SET completed_at = CURRENT_TIMESTAMP, status = $2, game_day = $3, phase = $4 WHERE id = $1`,
      [runId, status, after.day, `daily_economy:${after.watermark}`],
    );
    return { schedulerRunId: runId, day: lastTick.day, minute: lastTick.minute, safeProcessedGameDay: after.watermark, settlementWatermark: after.watermark, settlementBacklog: Math.max(0, after.day - 1 - after.watermark), settledDays, settlementStatus: lastTick.settlementStatus, marketSettlements: market.batchesProcessed };
  } catch (error) {
    await repository.query("UPDATE scheduler_runs SET completed_at = CURRENT_TIMESTAMP, status = 'failed' WHERE id = $1", [runId]).catch(() => undefined);
    console.error('Scheduler heartbeat failed', error instanceof Error ? error.message : String(error));
    throw error;
  }
}
