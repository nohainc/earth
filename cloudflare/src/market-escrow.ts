import type { PostgresRepository } from './repository.ts';

export type EscrowEntry = { accountId: string; delta: bigint; assetId: number; reason: string };
export type MarketReservation = { id: string; order_id: string; escrow_account_id: string; asset_id: number; reserved_units: string; remaining_units: string; status: string };

async function houseEconomicId(tx: PostgresRepository, ownerId: string): Promise<string> {
  const result = await tx.query<{ economic_id: string }>(
    `SELECT o.economic_id::TEXT AS economic_id FROM owner_registry o
      WHERE o.id = COALESCE((SELECT house_id FROM humans WHERE id = $1), $1) AND o.owner_type = 'HOUSE'`,
    [ownerId],
  );
  if (!result.rows[0]) throw new Error('Market access is restricted to House owners');
  return result.rows[0].economic_id;
}

export async function marketAccount(tx: PostgresRepository, ownerId: string, assetId: number, accountType?: 'WALLET' | 'INVENTORY' | 'MARKET_ESCROW'): Promise<string | null> {
  const economicId = await houseEconomicId(tx, ownerId);
  const expectedType = accountType ?? (assetId === 1 ? 'WALLET' : 'INVENTORY');
  const result = await tx.query<{ account_id: string }>(
    `SELECT a.id::TEXT AS account_id FROM economic_accounts a
      WHERE a.owner_economic_id = $1 AND a.asset_id = $2 AND a.account_type = $3 AND a.status = 'ACTIVE' LIMIT 1`,
    [economicId, assetId, expectedType],
  );
  return result.rows[0]?.account_id ?? null;
}

export async function marketEconomicAccount(tx: PostgresRepository, economicId: string, assetId: number, accountType?: 'WALLET' | 'INVENTORY' | 'MARKET_ESCROW'): Promise<string | null> {
  const expectedType = accountType ?? (assetId === 1 ? 'WALLET' : 'INVENTORY');
  const result = await tx.query<{ account_id: string }>(
    `SELECT a.id::TEXT AS account_id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      WHERE a.owner_economic_id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = $2 AND a.account_type = $3 AND a.status = 'ACTIVE' LIMIT 1`,
    [economicId, assetId, expectedType],
  );
  return result.rows[0]?.account_id ?? null;
}

export async function ensureMarketEscrow(tx: PostgresRepository, ownerId: string, assetId: number): Promise<string> {
  const economicId = await houseEconomicId(tx, ownerId);
  const existing = await marketAccount(tx, ownerId, assetId, 'MARKET_ESCROW');
  if (existing) return existing;
  const created = await tx.query<{ account_id: string }>(
    `INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance_units, status)
     VALUES ($1, $2, 'MARKET_ESCROW', 0, 'ACTIVE')
     ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING RETURNING id::TEXT AS account_id`,
    [economicId, assetId],
  );
  const accountId = created.rows[0]?.account_id ?? await marketAccount(tx, ownerId, assetId, 'MARKET_ESCROW');
  if (!accountId) throw new Error('Unable to create House market escrow account');
  return accountId;
}

export async function postEscrowTransaction(tx: PostgresRepository, day: number, correlationId: string, sourceId: string, entries: EscrowEntry[]): Promise<boolean> {
  if (entries.length < 2) throw new Error('Escrow movement requires at least two entries');
  const result = await tx.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_transaction($1, $2, 0, 'MARKET_TRADE', 'MARKET', $3, 'market-v4', $4::jsonb)`,
    [correlationId, day, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, asset_id: entry.assetId, delta_units: entry.delta.toString(), reason_code: entry.reason })))],
  );
  if (!result.rows[0]) throw new Error('Market escrow transaction returned no result');
  return Boolean(result.rows[0].created);
}

export async function postSettlementBatch(tx: PostgresRepository, day: number, correlationId: string, sourceId: string, entries: EscrowEntry[]): Promise<{ transactionId: string; created: boolean }> {
  if (entries.length < 2) throw new Error('Settlement batch requires at least two entries');
  const result = await tx.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_settlement_batch($1, $2, 0, 'MARKET', $3, 'market-v4', $4::jsonb)`,
    [correlationId, day, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, asset_id: entry.assetId, delta_units: entry.delta.toString(), reason_code: entry.reason })))],
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

export async function reserveForOrder(tx: PostgresRepository, input: { ownerId: string; assetId: number; sourceAccountId: string; amountUnits: bigint; orderId: string; gameDay: number; reason: string }): Promise<string> {
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
  await postEscrowTransaction(tx, input.gameDay, `market-order:${input.orderId}:reserve`, input.orderId, [
    { accountId: input.sourceAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason },
    { accountId: escrowAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason },
  ]);
  return escrowAccountId;
}

export async function updateReservationRemaining(tx: PostgresRepository, orderId: string, assetId: number, movedUnits: bigint, finalStatus?: 'CONSUMED' | 'RELEASED'): Promise<void> {
  if (movedUnits < 0n) throw new Error('Reservation movement must be non-negative');
  const result = await tx.query(
    `UPDATE market_order_reservations SET remaining_units = remaining_units - $1,
       status = COALESCE($2, CASE WHEN remaining_units - $1 = 0 THEN 'CONSUMED' ELSE status END), updated_at = CURRENT_TIMESTAMP
     WHERE order_id = $3 AND asset_id = $4 AND status = 'ACTIVE' AND remaining_units >= $1`,
    [movedUnits.toString(), finalStatus ?? null, orderId, assetId],
  );
  if (result.rowCount !== 1) throw new Error(`Market reservation is missing or insufficient for order ${orderId}`);
}

export async function releaseReservation(tx: PostgresRepository, input: { escrowAccountId: string; destinationAccountId: string; assetId: number; amountUnits: bigint; orderId: string; gameDay: number; reason: string }): Promise<boolean> {
  if (input.amountUnits <= 0n) return false;
  const posted = await postEscrowTransaction(tx, input.gameDay, `market-order:${input.orderId}:release`, input.orderId, [
    { accountId: input.escrowAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason },
    { accountId: input.destinationAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason },
  ]);
  if (posted) await updateReservationRemaining(tx, input.orderId, input.assetId, input.amountUnits, 'RELEASED');
  return posted;
}
