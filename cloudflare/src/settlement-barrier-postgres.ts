import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime, getSettlementCursor, type SettlementCursorState } from './world-clock-postgres.ts';

export class SettlementCatchupBarrierError extends Error {
  readonly code: string;
  readonly statusCode = 409;
  readonly status = 409;
  readonly currentGameDay: number;
  readonly settledThroughGameDay: number;
  readonly lastClosedGameDay: number;
  readonly backlogDays: number;
  readonly failedGameDay?: number | null;
  readonly failedPhase?: string | null;
  readonly failedError?: string | null;

  constructor(cursor: SettlementCursorState, currentGameDay: number) {
    const isFailed = cursor.status === 'FAILED';
    const message = isFailed
      ? `Economic settlement failed on day ${cursor.failedGameDay} (phase: ${cursor.failedPhase ?? 'unknown'}, error: ${cursor.failedError ?? 'unknown'}). Economic transactions are paused until resolved.`
      : `Economic settlement is currently catching up (settled through day ${cursor.settledThroughGameDay}, last closed day ${cursor.lastClosedGameDay}, current day ${currentGameDay}). Economic transactions are temporarily paused until settlement completes.`;
    super(message);
    this.name = 'SettlementCatchupBarrierError';
    this.code = isFailed ? 'WORLD_SETTLEMENT_FAILED' : 'WORLD_SETTLEMENT_CATCHING_UP';
    this.currentGameDay = currentGameDay;
    this.settledThroughGameDay = cursor.settledThroughGameDay;
    this.lastClosedGameDay = cursor.lastClosedGameDay;
    this.backlogDays = cursor.backlogDays;
    this.failedGameDay = cursor.failedGameDay ?? null;
    this.failedPhase = cursor.failedPhase ?? null;
    this.failedError = cursor.failedError ?? null;
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
        ...(this.failedGameDay != null ? {
          failedGameDay: this.failedGameDay,
          failedPhase: this.failedPhase,
          failedError: this.failedError,
        } : {}),
      },
      { status: 409 },
    );
  }
}

export type EconomicMutationContext = SettlementCursorState & {
  gameDay: number;
  gameMinute: number;
  totalGameMinutes: number;
};

export function isSettlementBarrierError(error: unknown): error is SettlementCatchupBarrierError {
  return error instanceof SettlementCatchupBarrierError || (Boolean(error) && typeof error === 'object' && (error as { name?: unknown }).name === 'SettlementCatchupBarrierError');
}

/**
 * Asserts that economic daily settlement is completely caught up through lastClosedGameDay.
 * Throws SettlementCatchupBarrierError if settlement is behind or failed.
 */
export async function assertEconomyCaughtUp(
  repository: PostgresRepository | { query: PostgresRepository['query'] },
): Promise<EconomicMutationContext> {
  const clock = await readAuthoritativeGameTime(repository);
  const cursor = await getSettlementCursor(repository, clock.gameDay);

  if (cursor.settledThroughGameDay < cursor.lastClosedGameDay || cursor.status === 'FAILED') {
    throw new SettlementCatchupBarrierError(cursor, clock.gameDay);
  }

  return {
    ...cursor,
    gameDay: clock.gameDay,
    gameMinute: clock.gameMinute,
    totalGameMinutes: clock.totalGameMinutes,
  };
}

/**
 * Runs an economic mutation inside a PostgreSQL transaction, asserting that
 * economic daily settlement is completely caught up before executing the mutation.
 * If settlement is behind or failed, SettlementCatchupBarrierError is thrown (HTTP 409).
 */
export async function runEconomicMutation<T>(
  repository: PostgresRepository,
  mutation: (tx: PostgresRepository, context: EconomicMutationContext) => Promise<T>,
): Promise<T> {
  return repository.transaction(async (tx) => {
    const context = await assertEconomyCaughtUp(tx);
    return mutation(tx, context);
  });
}

export const withSettledEconomy = runEconomicMutation;

export {
  postEconomicTransaction,
  postSettlementTransaction,
  type EconomicEntry,
  type EconomicTransactionInput,
  type EconomicTransactionResult,
  type SettlementTransactionInput,
} from './economic-transaction-postgres.ts';
