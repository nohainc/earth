import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime, getSettlementCursor, type SettlementCursorState } from './world-clock-postgres.ts';

export class SettlementCatchupBarrierError extends Error {
  readonly code = 'WORLD_SETTLEMENT_CATCHING_UP';
  readonly currentGameDay: number;
  readonly settledThroughGameDay: number;
  readonly lastClosedGameDay: number;
  readonly backlogDays: number;

  constructor(cursor: SettlementCursorState, currentGameDay: number) {
    super(
      `Economic settlement is currently catching up (settled through day ${cursor.settledThroughGameDay}, last closed day ${cursor.lastClosedGameDay}, current day ${currentGameDay}). Economic transactions are temporarily paused until settlement completes.`,
    );
    this.name = 'SettlementCatchupBarrierError';
    this.currentGameDay = currentGameDay;
    this.settledThroughGameDay = cursor.settledThroughGameDay;
    this.lastClosedGameDay = cursor.lastClosedGameDay;
    this.backlogDays = cursor.backlogDays;
  }

  toResponse(): Response {
    return Response.json(
      {
        ok: false,
        code: this.code,
        error: this.message,
        currentGameDay: this.currentGameDay,
        settledThroughGameDay: this.settledThroughGameDay,
        lastClosedGameDay: this.lastClosedGameDay,
        backlogDays: this.backlogDays,
      },
      { status: 409 },
    );
  }
}

/**
 * Asserts that economic daily settlement is completely caught up through lastClosedGameDay.
 * Throws SettlementCatchupBarrierError if settlement is behind.
 */
export async function assertEconomyCaughtUp(
  repository: PostgresRepository | { query: PostgresRepository['query'] },
): Promise<SettlementCursorState> {
  const clock = await readAuthoritativeGameTime(repository);
  const cursor = await getSettlementCursor(repository, clock.gameDay);

  if (cursor.settledThroughGameDay < cursor.lastClosedGameDay) {
    throw new SettlementCatchupBarrierError(cursor, clock.gameDay);
  }

  return cursor;
}
