import type { PostgresRepository } from './repository.ts';
import { runWorldSchedulerTick } from './scheduler-postgres.ts';
import { processEndOfDayAutomation } from './daily-automation.ts';
import { processDueMarketBatches } from './market-scheduler.ts';

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
};

function positiveInteger(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

async function readSettlementPosition(repository: PostgresRepository): Promise<{ day: number; watermark: number }> {
  const result = await repository.query<{ day: string; watermark: string }>(
    `SELECT w.game_day::text AS day,
            earth_settlement_watermark(w.game_day)::text AS watermark
       FROM world_state w
      WHERE w.id = 'WORLD'`,
  );
  return {
    day: Number(result.rows[0]?.day ?? 0),
    watermark: Number(result.rows[0]?.watermark ?? 0),
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
  const workerInstanceId = `scheduler:${crypto.randomUUID()}`;
  const before = await readSettlementPosition(repository);
  const run = await repository.query<{ id: string }>(
    `INSERT INTO scheduler_runs (scheduled_time, worker_instance_id, status, game_day, settlement_watermark_before, backlog_before)
     VALUES ($1,$2,'running',$3,$4,GREATEST(0,$3 - 1 - $4)) RETURNING id`,
    [Number(scheduledTime), workerInstanceId, before.day, before.watermark],
  );
  const runId = run.rows[0]?.id;
  let settledDays = 0;
  let actionsProcessed = 0;
  let lastTick: Awaited<ReturnType<typeof runWorldSchedulerTick>>;
  try {
    lastTick = await runWorldSchedulerTick(repository, String(scheduledTime));
    if (lastTick.settlementStatus === 'completed') settledDays += 1;
    let position = await readSettlementPosition(repository);
    while (position.watermark < position.day - 1 && settledDays < maxCatchupDays && Date.now() - startedAt < workBudgetMs) {
      const nextDay = position.watermark + 1;
      lastTick = await runWorldSchedulerTick(repository, `${scheduledTime}:catchup:${nextDay}`);
      if (lastTick.settlementStatus === 'busy' || lastTick.settlementStatus === 'failed') break;
      if (lastTick.settlementStatus === 'completed') settledDays += 1;
      const nextPosition = await readSettlementPosition(repository);
      if (nextPosition.watermark <= position.watermark) break;
      position = nextPosition;
    }
    position = await readSettlementPosition(repository);
    actionsProcessed = await processEndOfDayAutomation(repository, position.watermark, 1439);
    const market = position.watermark > 0
      ? await processDueMarketBatches(repository, position.watermark, Math.max(1, Math.min(workBudgetMs, 10_000)), workerInstanceId)
      : { batchesProcessed: 0, tradesCreated: 0, busy: false };
    await repository.query('UPDATE world_state SET last_scheduler_at = to_timestamp($1 / 1000.0) WHERE id = \'WORLD\'', [Number(scheduledTime)]);
    const after = await readSettlementPosition(repository);
    const status = lastTick.settlementStatus === 'busy' ? 'busy' : lastTick.settlementStatus === 'failed' ? 'failed' : after.watermark < after.day - 1 ? 'partial' : 'completed';
    await repository.query(
      `UPDATE scheduler_runs SET completed_at = CURRENT_TIMESTAMP, status = $2, game_day = $3, game_minute = $4,
         settlement_watermark_after = $5, backlog_after = GREATEST(0,$3 - 1 - $5), settlement_days_processed = $6,
         actions_processed = $7, market_batches_processed = $8 WHERE id = $1`,
      [runId, status, after.day, lastTick.minute, after.watermark, settledDays, actionsProcessed, market.batchesProcessed],
    );
    return { schedulerRunId: runId, day: lastTick.day, minute: lastTick.minute, safeProcessedGameDay: after.watermark, settlementWatermark: after.watermark, settlementBacklog: Math.max(0, after.day - 1 - after.watermark), settledDays, settlementStatus: lastTick.settlementStatus, marketSettlements: market.batchesProcessed };
  } catch (error) {
    await repository.query('UPDATE scheduler_runs SET completed_at = CURRENT_TIMESTAMP, status = \'failed\', error_stage = \'heartbeat\', error_message = $2 WHERE id = $1', [runId, error instanceof Error ? error.message.slice(0, 2000) : 'Unknown scheduler error']).catch(() => undefined);
    throw error;
  }
}
