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
  if (controlStatus === 'paused') {
    status = 'PAUSED';
  } else if (backlogDays > 0) {
    status = 'CATCHING_UP';
  }

  return {
    settledThroughGameDay,
    lastClosedGameDay: lastClosed,
    backlogDays,
    status,
  };
}
