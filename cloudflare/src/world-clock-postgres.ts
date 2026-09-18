import type { PostgresRepository } from './repository.ts';

export type AuthoritativeGameTime = {
  gameDay: number;
  gameMinute: number;
  totalGameMinutes: number;
  genesisAt: string;
  serverNow: string;
  elapsedRealSeconds: number;
  realSecondsPerGameMinute: number;
};

export type SettlementCursorState = {
  settledThroughGameDay: number;
  lastClosedGameDay: number;
  backlogDays: number;
  status: 'CURRENT' | 'CATCHING_UP' | 'FAILED' | 'PAUSED';
  failedGameDay?: number | null;
  failedPhase?: string | null;
  failedError?: string | null;
};

/**
 * Converts game day (1-based) and game minute (0-1439) into continuous absolute game minutes.
 * Absolute minute 0 = Day 1, 00:00.
 */
export function toAbsoluteGameMinute(gameDay: number, gameMinute: number): number {
  return (Math.max(1, Math.floor(gameDay)) - 1) * 1440 + Math.max(0, Math.min(1439, Math.floor(gameMinute)));
}

/**
 * Converts continuous absolute game minutes into 1-based game day and minute.
 */
export function fromAbsoluteGameMinute(totalMinutes: number): { gameDay: number; gameMinute: number } {
  const safeMin = Math.max(0, Math.floor(totalMinutes));
  return {
    gameDay: Math.floor(safeMin / 1440) + 1,
    gameMinute: safeMin % 1440,
  };
}

/**
 * Derives the last game day eligible for completed daily settlement.
 * The current open day is never settled.
 */
export function lastClosedGameDay(clockOrDay: { gameDay: number } | number): number {
  const day = typeof clockOrDay === 'number' ? clockOrDay : clockOrDay.gameDay;
  return Math.max(0, Math.floor(day) - 1);
}

/**
 * Reads the authoritative world clock derived from PostgreSQL CURRENT_TIMESTAMP - genesis_at.
 * Fails closed if genesis_at is unconfigured.
 */
export async function readAuthoritativeGameTime(
  repository: PostgresRepository | { query: PostgresRepository['query'] },
): Promise<AuthoritativeGameTime> {
  const result = await repository.query<{
    game_day: string | number;
    game_minute: number;
    total_game_minutes: string | number;
    genesis_at: string | Date;
    server_now: string | Date;
    elapsed_real_seconds: string | number;
    real_seconds_per_game_minute: number;
  }>('SELECT * FROM earth_get_current_game_time()');

  const row = result.rows[0];
  if (!row) {
    throw new Error('Authoritative world clock is unavailable from database');
  }

  const genesisAt = row.genesis_at instanceof Date ? row.genesis_at.toISOString() : String(row.genesis_at);
  const serverNow = row.server_now instanceof Date ? row.server_now.toISOString() : String(row.server_now);

  return {
    gameDay: Number(row.game_day),
    gameMinute: Number(row.game_minute),
    totalGameMinutes: Number(row.total_game_minutes),
    genesisAt,
    serverNow,
    elapsedRealSeconds: Number(row.elapsed_real_seconds),
    realSecondsPerGameMinute: Number(row.real_seconds_per_game_minute ?? 1),
  };
}

/**
 * Reads the O(1) contiguous settlement cursor and derives backlog relative to lastClosedGameDay.
 * Detects terminal failures on the next settlement day (settledThroughGameDay + 1).
 */
export async function getSettlementCursor(
  repository: PostgresRepository | { query: PostgresRepository['query'] },
  currentGameDay?: number,
): Promise<SettlementCursorState> {
  const control = await repository.query<{
    status: string;
    settled_through_game_day: string | number;
  }>("SELECT status, settled_through_game_day FROM daily_settlement_control WHERE id = 'WORLD'");

  const row = control.rows[0];
  const settledThroughGameDay = Number(row?.settled_through_game_day ?? 0);
  const controlStatus = String(row?.status ?? 'awaiting_baseline');

  let day = currentGameDay;
  if (day == null) {
    const clock = await readAuthoritativeGameTime(repository);
    day = clock.gameDay;
  }

  const lastClosed = lastClosedGameDay(day);
  const backlogDays = Math.max(0, lastClosed - settledThroughGameDay);

  let status: SettlementCursorState['status'] = 'CURRENT';
  let failedGameDay: number | null = null;
  let failedPhase: string | null = null;
  let failedError: string | null = null;

  if (controlStatus === 'paused') {
    status = 'PAUSED';
  } else if (backlogDays > 0) {
    const nextDay = settledThroughGameDay + 1;
    const failureRun = await repository.query<{
      status: string;
      current_phase: string | null;
      error_message: string | null;
    }>(
      "SELECT status, current_phase, error_message FROM daily_settlement_runs WHERE game_day = $1 AND status = 'failed'",
      [nextDay],
    ).catch(() => ({ rows: [] }));

    if (failureRun.rows.length > 0 && failureRun.rows[0]?.status === 'failed') {
      status = 'FAILED';
      failedGameDay = nextDay;
      failedPhase = failureRun.rows[0].current_phase ?? null;
      failedError = failureRun.rows[0].error_message ?? null;
    } else {
      const phaseFailure = await repository.query<{
        phase_id: string;
        error_message: string | null;
      }>(
        `SELECT phase_id, error_message
           FROM daily_settlement_phase_runs
          WHERE game_day = $1
            AND status = 'failed'
          ORDER BY phase_order, shard
          LIMIT 1`,
        [nextDay],
      ).catch(() => ({ rows: [] }));

      if (phaseFailure.rows[0]) {
        status = 'FAILED';
        failedGameDay = nextDay;
        failedPhase = phaseFailure.rows[0].phase_id;
        failedError = phaseFailure.rows[0].error_message ?? null;
      } else {
        status = 'CATCHING_UP';
      }
    }
  }

  return {
    settledThroughGameDay,
    lastClosedGameDay: lastClosed,
    backlogDays,
    status,
    ...(failedGameDay != null ? { failedGameDay, failedPhase, failedError } : {}),
  };
}

/**
 * Projects a duration in game minutes from a start day and minute into absolute minutes and completion position.
 */
export function projectDeadline(
  startDay: number,
  startMinute: number,
  durationMinutes: number,
): {
  startedAbsoluteMinute: number;
  completionAbsoluteMinute: number;
  completionGameDay: number;
  completionGameMinute: number;
} {
  const startedAbsoluteMinute = toAbsoluteGameMinute(startDay, startMinute);
  const completionAbsoluteMinute = startedAbsoluteMinute + Math.max(0, Math.floor(durationMinutes));
  const completion = fromAbsoluteGameMinute(completionAbsoluteMinute);
  return {
    startedAbsoluteMinute,
    completionAbsoluteMinute,
    completionGameDay: completion.gameDay,
    completionGameMinute: completion.gameMinute,
  };
}

/**
 * Evaluates whether an absolute completion minute or day/minute has elapsed relative to current clock.
 */
export function isDeadlineDue(
  completionOrDay: { completionAbsoluteMinute?: number; gameDay?: number; gameMinute?: number } | number,
  currentClock: AuthoritativeGameTime | { totalGameMinutes: number },
): boolean {
  const currentAbs = currentClock.totalGameMinutes;
  if (typeof completionOrDay === 'number') {
    return currentAbs >= completionOrDay;
  }
  if (completionOrDay.completionAbsoluteMinute != null) {
    return currentAbs >= completionOrDay.completionAbsoluteMinute;
  }
  const day = completionOrDay.gameDay ?? 1;
  const minute = completionOrDay.gameMinute ?? 0;
  return currentAbs >= toAbsoluteGameMinute(day, minute);
}
