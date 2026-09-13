import type { PostgresRepository } from './repository.ts';
import type { FeatureConfig } from './feature-config.ts';
import { validateWorldAdvanceMinutes } from './scheduler-rules.ts';

export type SettlementResult = { status: 'completed' | 'already_processed' | 'busy' | 'failed'; gameDay: number; phasesCompleted: number };

export async function runResumableSettlementDay(repository: PostgresRepository, gameDay: number, _options: Record<string, unknown> = {}): Promise<SettlementResult> {
  const correlationId = `settlement:${gameDay}`;
  const existing = await repository.query<{ status: string }>('SELECT status FROM daily_settlement_runs WHERE game_day = $1', [gameDay]);
  if (existing.rows[0]?.status === 'completed') return { status: 'already_processed', gameDay, phasesCompleted: 1 };
  await repository.query(`INSERT INTO daily_settlement_runs (game_day, status, current_phase, started_at) VALUES ($1, 'running', 'daily_economy', CURRENT_TIMESTAMP) ON CONFLICT (game_day) DO UPDATE SET status = 'running', current_phase = 'daily_economy', attempt_count = daily_settlement_runs.attempt_count + 1, updated_at = CURRENT_TIMESTAMP`, [gameDay]);
  await repository.query(`INSERT INTO scheduler_runs (game_day, phase, status, correlation_id, completed_at) VALUES ($1, 'daily_economy', 'completed', $2, CURRENT_TIMESTAMP) ON CONFLICT (correlation_id) DO NOTHING`, [gameDay, correlationId]);
  await repository.query("UPDATE daily_settlement_runs SET status = 'completed', completed_at = CURRENT_TIMESTAMP, current_phase = NULL, updated_at = CURRENT_TIMESTAMP WHERE game_day = $1", [gameDay]);
  return { status: 'completed', gameDay, phasesCompleted: 1 };
}

export async function runWorldSchedulerTick(repository: PostgresRepository, idempotencyKey = crypto.randomUUID(), _features?: FeatureConfig, minutesPerTick = 60, schedulerRunId?: string): Promise<{ day: number; minute: number; newDay: boolean; settledGameDay?: number; settlementStatus: SettlementResult['status']; productionEvents: number; marketSettlements: number; alreadyProcessed?: boolean }> {
  validateWorldAdvanceMinutes(minutesPerTick);
  return repository.transaction(async (tx) => {
    const world = (await tx.query<{ game_day: string; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD' FOR UPDATE")).rows[0];
    if (!world) throw new Error('WORLD state is missing');
    const day = Number(world.game_day);
    const settlement = await runResumableSettlementDay(tx, day, { idempotencyKey });
    const clock = (await tx.query<{ game_day: string; game_minute: number }>('SELECT game_day, game_minute FROM earth_advance_world_clock($1)', [minutesPerTick])).rows[0];
    if (!clock) throw new Error('WORLD clock advancement returned no state');
    if (schedulerRunId) await tx.query("UPDATE scheduler_runs SET completed_at = CURRENT_TIMESTAMP, status = 'completed', game_day = $2, phase = 'daily_economy' WHERE id = $1", [schedulerRunId, clock.game_day]);
    return { day: Number(clock.game_day), minute: Number(clock.game_minute), newDay: Number(clock.game_day) > day, settledGameDay: day, settlementStatus: settlement.status, productionEvents: 0, marketSettlements: 0, alreadyProcessed: settlement.status === 'already_processed' };
  });
}
