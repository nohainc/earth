import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime, type AuthoritativeGameTime } from './world-clock-postgres.ts';
import type { EconomicMutationContext } from './settlement-barrier-postgres.ts';

export type EconomicEntry = {
  account_id?: string | number;
  asset_id?: number;
  delta_units?: string | bigint | number;
  reason_code?: string;
  /** @deprecated Use snake_case fields in new call sites. Kept for migrated modules. */
  accountId?: string | number;
  /** @deprecated Use snake_case fields in new call sites. Kept for migrated modules. */
  assetId?: number;
  /** @deprecated Use snake_case fields in new call sites. Kept for migrated modules. */
  deltaUnits?: string | bigint | number;
  /** @deprecated Use snake_case fields in new call sites. Kept for migrated modules. */
  reasonCode?: string;
};

export type EconomicTransactionInput = {
  correlationId: string;
  kind: string;
  sourceType: string;
  sourceId: string;
  rulesVersion: string;
  entries: EconomicEntry[];
};

export type EconomicTransactionResult = {
  transactionId: string;
  gameDay: number;
  gameMinute: number;
  created?: boolean;
};

export type SettlementTransactionInput = EconomicTransactionInput & {
  gameDay: number;
  gameMinute?: number;
};

export type GameTimeContext =
  | EconomicMutationContext
  | AuthoritativeGameTime
  | { gameDay: number; gameMinute: number };

/**
 * Authoritative economic transaction posting helper for interactive operations.
 * Reads authoritative gameDay and gameMinute from PostgreSQL if not already provided
 * via EconomicMutationContext / GameTimeContext.
 *
 * Guarantees that interactive transactions are never posted with arbitrary, stale,
 * or end-of-day (1439) timestamps.
 */
export async function postEconomicTransaction(
  tx: PostgresRepository,
  input: EconomicTransactionInput,
  context?: GameTimeContext,
): Promise<EconomicTransactionResult> {
  let gameDay: number;
  let gameMinute: number;

  if (context && typeof context.gameDay === 'number' && typeof context.gameMinute === 'number') {
    gameDay = context.gameDay;
    gameMinute = context.gameMinute;
  } else {
    const clock = await readAuthoritativeGameTime(tx);
    gameDay = clock.gameDay;
    gameMinute = clock.gameMinute;
  }

  if (gameDay < 1 || gameMinute < 0 || gameMinute > 1439) {
    throw new Error(`Invalid authoritative game time for transaction: day ${gameDay}, minute ${gameMinute}`);
  }

  if (!input.entries || input.entries.length === 0) {
    throw new Error(`Economic transaction ${input.correlationId} must contain at least one entry`);
  }

  const normalizedEntries = input.entries.map((e) => {
    const accountId = e.account_id ?? e.accountId;
    const assetId = e.asset_id ?? e.assetId;
    const deltaUnits = e.delta_units ?? e.deltaUnits;
    const reasonCode = e.reason_code ?? e.reasonCode;
    return {
      account_id: String(accountId ?? ''),
      asset_id: Number(assetId ?? 0),
      delta_units: String(deltaUnits ?? 0),
      ...(reasonCode ? { reason_code: reasonCode } : {}),
    };
  });

  const result = await tx.query<{ transaction_id?: string; created?: boolean; id?: string }>(
    `SELECT earth_post_transaction($1, $2, $3, $4, $5, $6, $7, $8::JSONB) AS transaction_id`,
    [
      input.correlationId,
      gameDay,
      gameMinute,
      input.kind,
      input.sourceType,
      input.sourceId,
      input.rulesVersion,
      JSON.stringify(normalizedEntries),
    ],
  );

  const row = result.rows[0];
  const txId = row?.transaction_id ?? row?.id;
  if (!txId) throw new Error(`Economic transaction ${input.correlationId} returned no result (no transaction ID)`);

  return {
    transactionId: String(txId),
    gameDay,
    gameMinute,
    created: row.created !== false,
  };
}

/**
 * Dedicated helper for scheduled daily settlement and end-of-day automations.
 * Uses explicit settlement game day and defaults gameMinute to 1439 (end of day).
 */
export async function postSettlementTransaction(
  tx: PostgresRepository,
  input: SettlementTransactionInput,
): Promise<EconomicTransactionResult> {
  const gameDay = input.gameDay;
  const gameMinute = input.gameMinute ?? 1439;

  if (gameDay < 1 || gameMinute < 0 || gameMinute > 1439) {
    throw new Error(`Invalid settlement game time: day ${gameDay}, minute ${gameMinute}`);
  }

  if (!input.entries || input.entries.length === 0) {
    throw new Error(`Settlement transaction ${input.correlationId} must contain at least one entry`);
  }

  const normalizedEntries = input.entries.map((e) => {
    const accountId = e.account_id ?? e.accountId;
    const assetId = e.asset_id ?? e.assetId;
    const deltaUnits = e.delta_units ?? e.deltaUnits;
    const reasonCode = e.reason_code ?? e.reasonCode;
    return {
      account_id: String(accountId ?? ''),
      asset_id: Number(assetId ?? 0),
      delta_units: String(deltaUnits ?? 0),
      ...(reasonCode ? { reason_code: reasonCode } : {}),
    };
  });

  const result = await tx.query<{ transaction_id?: string; created?: boolean; id?: string }>(
    `SELECT earth_post_transaction($1, $2, $3, $4, $5, $6, $7, $8::JSONB) AS transaction_id`,
    [
      input.correlationId,
      gameDay,
      gameMinute,
      input.kind,
      input.sourceType,
      input.sourceId,
      input.rulesVersion,
      JSON.stringify(normalizedEntries),
    ],
  );

  const row = result.rows[0];
  const txId = row?.transaction_id ?? row?.id;
  if (!txId) throw new Error(`Settlement transaction ${input.correlationId} returned no result (no transaction ID)`);

  return {
    transactionId: String(txId),
    gameDay,
    gameMinute,
    created: row.created !== false,
  };
}
