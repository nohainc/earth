import type { PostgresRepository } from './repository.ts';
import type { DailySettlementPhase } from './daily-settlement-phases.ts';

export type SettlementWork = { id: string; game_day: string; phase_id: string; shard: number; status: 'pending' | 'running' | 'completed' | 'failed'; attempt_count: number; lease_owner: string | null };

// @mutation-boundary atomic-sql: lease transitions are guarded by single SQL statements/functions.
export async function ensureSettlementWork(repository: PostgresRepository, gameDay: number, phases: readonly DailySettlementPhase[], shardCount: number): Promise<void> {
  for (const phase of phases.filter((item) => item.status === 'required')) {
    const count = phase.shardMode === 'owner-shards' ? shardCount : 1;
    for (let shard = 0; shard < count; shard += 1) {
      await repository.query(`INSERT INTO daily_settlement_phase_runs (game_day, phase_id, phase_order, shard, status, correlation_id) VALUES ($1, $2, $3, $4, 'pending', $5) ON CONFLICT (game_day, phase_id, shard) DO NOTHING`, [gameDay, phase.id, phase.order, shard, `settlement:${gameDay}:${phase.id}:${shard}`]);
    }
  }
}

export async function claimSettlementWork(repository: PostgresRepository, gameDay: number, workerId: string, leaseSeconds = 30): Promise<SettlementWork | null> {
  const claimed = await repository.query<{ id: string }>('SELECT earth_claim_settlement_day($1, $2, $3) AS id', [gameDay, workerId, leaseSeconds]);
  if (!claimed.rows[0]?.id) return null;
  const result = await repository.query<SettlementWork>('SELECT id, game_day, phase_id, shard, status, attempt_count, lease_owner FROM daily_settlement_phase_runs WHERE id = $1', [claimed.rows[0].id]);
  return result.rows[0] ?? null;
}

export async function completeSettlementWork(repository: PostgresRepository, id: string, workerId: string): Promise<void> {
  const result = await repository.query(`UPDATE daily_settlement_phase_runs SET status = 'completed', lease_owner = NULL, lease_expires_at = NULL, completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1 AND status = 'running' AND lease_owner = $2`, [id, workerId]);
  if (result.rowCount !== 1) throw new Error('Settlement work lease lost');
}

export async function failSettlementWork(repository: PostgresRepository, id: string, workerId: string, error: unknown): Promise<void> {
  await repository.query('SELECT earth_fail_settlement_day($1, $2, $3)', [id, workerId, error instanceof Error ? error.message.slice(0, 1000) : String(error).slice(0, 1000)]);
}

export async function settlementWorkProgress(repository: PostgresRepository, gameDay: number) {
  const result = await repository.query<{ total: string; completed: string; pending: string; failed: string }>(`SELECT COUNT(*)::text AS total, COUNT(*) FILTER (WHERE status = 'completed')::text AS completed, COUNT(*) FILTER (WHERE status IN ('pending','running'))::text AS pending, COUNT(*) FILTER (WHERE status = 'failed')::text AS failed FROM daily_settlement_phase_runs WHERE game_day = $1`, [gameDay]);
  const row = result.rows[0] ?? { total: '0', completed: '0', pending: '0', failed: '0' };
  return { total: Number(row.total), completed: Number(row.completed), pending: Number(row.pending), failed: Number(row.failed) };
}
