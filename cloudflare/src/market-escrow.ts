import type { PostgresRepository } from './repository.ts';
import { postEconomicTransaction, postSettlementTransaction } from './economic-transaction-postgres.ts';
import type { EconomicMutationContext } from './settlement-barrier-postgres.ts';

export type EscrowEntry = { accountId: string; delta: bigint; assetId: number; reason: string };
export type MarketReservation = { id: string; order_id: string; escrow_account_id: string; asset_id: number; reserved_units: string; remaining_units: string; status: string };

export async function marketOwnerEconomicId(tx: PostgresRepository, ownerId: string): Promise<string> {
  const result = await tx.query<{ economic_id: string }>(
    `SELECT o.economic_id::TEXT AS economic_id
       FROM owner_registry o
      WHERE (o.id = $1 OR o.economic_id = $1 OR o.id = (SELECT house_id FROM humans WHERE id = $1))
        AND o.owner_type IN ('HOUSE', 'CORPORATION')
      LIMIT 1`,
    [ownerId],
  );
  if (!result.rows[0]) throw new Error('Market access requires an active House or Corporation owner');
  return result.rows[0].economic_id;
}

export async function marketAccount(tx: PostgresRepository, ownerId: string, assetId: number, accountType?: 'WALLET' | 'TREASURY' | 'INVENTORY' | 'MARKET_ESCROW'): Promise<string | null> {
  const economicId = await marketOwnerEconomicId(tx, ownerId);
  return marketEconomicAccount(tx, economicId, assetId, accountType);
}

export async function marketEconomicAccount(tx: PostgresRepository, economicId: string, assetId: number, accountType?: string): Promise<string | null> {
  const owner = (await tx.query<{ owner_type: string }>(
    'SELECT owner_type FROM owner_registry WHERE economic_id = $1', [economicId],
  )).rows[0];
  const defaultCreditAccount = owner?.owner_type === 'CORPORATION' ? 'TREASURY' : 'WALLET';
  const expectedType = accountType ?? (assetId === 1 ? defaultCreditAccount : 'INVENTORY');
  const result = await tx.query<{ account_id: string }>(
    `SELECT a.id::TEXT AS account_id FROM economic_accounts a
      WHERE a.owner_economic_id = $1 AND a.asset_id = $2 AND a.account_type = $3 AND a.status = 'ACTIVE' LIMIT 1`,
    [economicId, assetId, expectedType],
  );
  return result.rows[0]?.account_id ?? null;
}

export async function ensureMarketEscrow(tx: PostgresRepository, ownerId: string, assetId: number): Promise<string> {
  const economicId = await marketOwnerEconomicId(tx, ownerId);
  const existing = await marketAccount(tx, ownerId, assetId, 'MARKET_ESCROW');
  if (existing) return existing;
  const created = await tx.query<{ account_id: string }>(
    `INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance_units, status)
     VALUES ($1, $2, 'MARKET_ESCROW', 0, 'ACTIVE')
     ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING RETURNING id::TEXT AS account_id`,
    [economicId, assetId],
  );
  const accountId = created.rows[0]?.account_id ?? await marketAccount(tx, ownerId, assetId, 'MARKET_ESCROW');
  if (!accountId) throw new Error('Unable to create market escrow account');
  return accountId;
}

export async function postEscrowTransaction(tx: PostgresRepository, context: EconomicMutationContext, correlationId: string, sourceId: string, entries: EscrowEntry[]): Promise<boolean> {
  if (entries.length < 2) throw new Error('Escrow movement requires at least two entries');
  const result = await postEconomicTransaction(tx, {
    correlationId,
    kind: 'MARKET_TRADE',
    sourceType: 'MARKET',
    sourceId,
    rulesVersion: 'market-v4',
    entries: entries.map((entry) => ({
      accountId: entry.accountId,
      assetId: entry.assetId,
      deltaUnits: entry.delta.toString(),
      reasonCode: entry.reason,
    })),
  }, context);
  return Boolean(result.transactionId);
}

export async function postSettlementBatch(tx: PostgresRepository, settlementGameDay: number, settlementGameMinute: number, correlationId: string, sourceId: string, entries: EscrowEntry[]): Promise<{ transactionId: string; created: boolean }> {
  if (entries.length < 2) throw new Error('Settlement batch requires at least two entries');
  const result = await tx.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_settlement_batch($1, $2, $3, 'MARKET', $4, 'market-v4', $5::jsonb)`,
    [correlationId, settlementGameDay, settlementGameMinute, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, asset_id: entry.assetId, delta_units: entry.delta.toString(), reason_code: entry.reason })))],
  );
  if (!result.rows[0]) throw new Error('Market settlement batch returned no result');
  return { transactionId: result.rows[0].transaction_id, created: Boolean(result.rows[0].created) };
}

export async function getMarketReservation(tx: PostgresRepository, orderId: string, assetId?: number): Promise<MarketReservation | null> {
  const result = await tx.query<MarketReservation>(
    `SELECT id::TEXT, order_id, escrow_account_id::TEXT, asset_id, reserved_units::TEXT, remaining_units::TEXT, status
       FROM market_order_reservations WHERE order_id = $1 AND ($2::INTEGER IS NULL OR asset_id = $2) ORDER BY id LIMIT 1`,
    [orderId, assetId ?? null],
  );
  return result.rows[0] ?? null;
}

export async function reserveForOrder(tx: PostgresRepository, input: { ownerId: string; assetId: number; sourceAccountId: string; amountUnits: bigint; orderId: string; reason: string }, context: EconomicMutationContext): Promise<string> {
  if (input.amountUnits <= 0n) throw new Error('Reservation amount must be positive');
  const escrowAccountId = await ensureMarketEscrow(tx, input.ownerId, input.assetId);
  const reservation = await tx.query<{ id: string }>(
    `INSERT INTO market_order_reservations (order_id, escrow_account_id, asset_id, reserved_units, remaining_units)
     VALUES ($1, $2, $3, $4, $4) ON CONFLICT (order_id, asset_id) DO NOTHING RETURNING id::TEXT`,
    [input.orderId, escrowAccountId, input.assetId, input.amountUnits.toString()],
  );
  if (!reservation.rows[0]) {
    const existing = await getMarketReservation(tx, input.orderId, input.assetId);
    if (!existing) throw new Error('Market reservation could not be recovered');
    return existing.escrow_account_id;
  }
  await postEscrowTransaction(tx, context, `market-order:${input.orderId}:reserve`, input.orderId, [
    { accountId: input.sourceAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason },
    { accountId: escrowAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason },
  ]);
  return escrowAccountId;
}

export type ReleaseReservationInput = {
  escrowAccountId: string;
  destinationAccountId: string;
  assetId: number;
  amountUnits: bigint;
  orderId: string;
  gameDay: number;
  reason?: string;
  context?: EconomicMutationContext;
  settlement?: { gameDay: number; gameMinute: number };
};

export async function releaseReservation(
  tx: PostgresRepository,
  inputOrReservation: ReleaseReservationInput | MarketReservation,
  gameDay?: number,
  sourceAccountId?: string,
  unfillableUnits?: bigint,
): Promise<void> {
  const input: ReleaseReservationInput = 'escrowAccountId' in inputOrReservation
    ? inputOrReservation
    : {
        escrowAccountId: inputOrReservation.escrow_account_id,
        destinationAccountId: sourceAccountId!,
        assetId: inputOrReservation.asset_id,
        amountUnits: unfillableUnits ?? 0n,
        orderId: inputOrReservation.order_id,
        gameDay: gameDay ?? 0,
        reason: 'market_order_release',
      };
  if (input.amountUnits <= 0n) return;
  const entries = [
    { accountId: input.escrowAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason ?? 'market_order_release' },
    { accountId: input.destinationAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason ?? 'market_order_release' },
  ];
  if (input.context) {
    await postEscrowTransaction(tx, input.context, `market-order:${input.orderId}:release:${input.gameDay}`, input.orderId, entries);
  } else if (input.settlement) {
    await postSettlementTransaction(tx, {
      correlationId: `market-order:${input.orderId}:release:${input.gameDay}`,
      kind: 'MARKET_TRADE', sourceType: 'MARKET', sourceId: input.orderId,
      rulesVersion: 'market-v4', entries: entries.map((entry) => ({ account_id: entry.accountId, asset_id: entry.assetId, delta_units: entry.delta.toString(), reason_code: entry.reason })),
      ...input.settlement,
    });
  } else {
    throw new Error('Market reservation release requires an interactive mutation context or settlement coordinates');
  }
  await tx.query(
    `UPDATE market_order_reservations
        SET remaining_units = GREATEST(0, remaining_units - $1::BIGINT),
            status = CASE WHEN remaining_units - $1::BIGINT <= 0 THEN 'RELEASED' ELSE status END
      WHERE order_id = $2 AND asset_id = $3`,
    [input.amountUnits.toString(), input.orderId, input.assetId],
  );
}

export async function updateReservationRemaining(
  tx: PostgresRepository,
  orderId: string,
  assetId: number,
  consumedUnits: bigint,
  finalStatus?: 'CONSUMED' | 'RELEASED',
): Promise<void> {
  await tx.query(
    `UPDATE market_order_reservations
        SET remaining_units = GREATEST(0, remaining_units - $1::BIGINT),
            status = CASE WHEN remaining_units - $1::BIGINT <= 0 THEN COALESCE($4, 'CONSUMED') ELSE status END
      WHERE order_id = $2 AND asset_id = $3`,
    [consumedUnits.toString(), orderId, assetId, finalStatus ?? null],
  );
}
