import type { PostgresRepository } from './repository.ts';

export type EscrowEntry = { accountId: string; delta: bigint; assetId: number; reason: string };

export async function marketAccount(tx: PostgresRepository, ownerId: string, assetId: number, accountType?: number, legacyAccountId?: string): Promise<string | null> {
  const result = await tx.query<{ account_id: string }>(
    `SELECT a.id::TEXT AS account_id
       FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      WHERE o.id = $1 AND a.asset_id = $2 AND a.status = 'active'
        AND ($3::SMALLINT IS NULL AND a.is_default_settlement OR a.account_type = $3)
        AND ($4::TEXT IS NULL OR a.legacy_account_id = $4)
      ORDER BY a.is_default_settlement DESC, a.id
      LIMIT 1`,
    [ownerId, assetId, accountType ?? null, legacyAccountId ?? null],
  );
  return result.rows[0]?.account_id ?? null;
}

export async function ensureMarketEscrow(tx: PostgresRepository, ownerId: string, assetId: number, orderId: string): Promise<string> {
  const legacyAccountId = `market-order:${orderId}`;
  const existing = await marketAccount(tx, ownerId, assetId, 6, legacyAccountId);
  if (existing) return existing;
  const owner = await tx.query<{ economic_id: string }>('SELECT economic_id::TEXT FROM owner_registry WHERE id = $1', [ownerId]);
  if (!owner.rows[0]) throw new Error('Economic owner not found');
  const created = await tx.query<{ account_id: string }>(
    `INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance, is_default_settlement, status, legacy_account_id)
     VALUES ($1,$2,6,0,FALSE,'active',$3)
     ON CONFLICT DO NOTHING
     RETURNING id::TEXT AS account_id`,
    [owner.rows[0].economic_id, assetId, legacyAccountId],
  );
  const accountId = created.rows[0]?.account_id ?? await marketAccount(tx, ownerId, assetId, 6, legacyAccountId);
  if (!accountId) throw new Error('Unable to create market escrow account');
  return accountId;
}

export async function postEscrowTransaction(
  tx: PostgresRepository,
  day: number,
  correlationId: string,
  sourceId: string,
  entries: EscrowEntry[],
): Promise<boolean> {
  if (entries.length < 2) throw new Error('Escrow movement requires at least two entries');
  const result = await tx.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,'MARKET_TRADE','market',$3,'market-v2',$4::jsonb)`,
    [correlationId, day, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, delta: entry.delta.toString(), reason_code: entry.reason })))],
  );
  if (!result.rows[0]) throw new Error('Market escrow transaction returned no result');
  return Boolean(result.rows[0].created);
}

export async function postSettlementBatch(
  tx: PostgresRepository,
  day: number,
  correlationId: string,
  sourceId: string,
  entries: EscrowEntry[],
): Promise<{ transactionId: string; created: boolean }> {
  if (entries.length < 2) throw new Error('Settlement batch requires at least two entries');
  const result = await tx.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_settlement_batch($1,$2,0,'market',$3,'market-v2',$4::jsonb)`,
    [correlationId, day, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, delta: entry.delta.toString(), reason_code: entry.reason })))],
  );
  if (!result.rows[0]) throw new Error('Market settlement batch returned no result');
  return { transactionId: result.rows[0].transaction_id, created: Boolean(result.rows[0].created) };
}

export async function reserveForOrder(
  tx: PostgresRepository,
  input: { ownerId: string; assetId: number; sourceAccountId: string; amountUnits: bigint; orderId: string; gameDay: number; reason: string },
): Promise<string> {
  if (input.amountUnits <= 0n) throw new Error('Reservation amount must be positive');
  const escrowAccountId = await ensureMarketEscrow(tx, input.ownerId, input.assetId, input.orderId);
  await postEscrowTransaction(tx, input.gameDay, `market-order:${input.orderId}:reserve`, input.orderId, [
    { accountId: input.sourceAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason },
    { accountId: escrowAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason },
  ]);
  return escrowAccountId;
}

export async function consumeReservation(
  tx: PostgresRepository,
  input: { escrowAccountId: string; destinationAccountId: string; assetId: number; amountUnits: bigint; orderId: string; gameDay: number; reason: string },
): Promise<boolean> {
  return postEscrowTransaction(tx, input.gameDay, `market-order:${input.orderId}:consume`, input.orderId, [
    { accountId: input.escrowAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason },
    { accountId: input.destinationAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason },
  ]);
}

export async function releaseReservation(
  tx: PostgresRepository,
  input: { escrowAccountId: string; destinationAccountId: string; assetId: number; amountUnits: bigint; orderId: string; gameDay: number; reason: string },
): Promise<boolean> {
  return postEscrowTransaction(tx, input.gameDay, `market-order:${input.orderId}:cancel`, input.orderId, [
    { accountId: input.escrowAccountId, delta: -input.amountUnits, assetId: input.assetId, reason: input.reason },
    { accountId: input.destinationAccountId, delta: input.amountUnits, assetId: input.assetId, reason: input.reason },
  ]);
}

export async function closeEscrowAccount(tx: PostgresRepository, escrowAccountId: string, orderId: string): Promise<void> {
  const result = await tx.query(
    `UPDATE economic_accounts
        SET status = 'closed', updated_at = CURRENT_TIMESTAMP
      WHERE id = $1 AND account_type = 6 AND status = 'active' AND balance = 0`,
    [escrowAccountId],
  );
  if (result.rowCount !== 1) throw new Error(`Cannot close non-empty or missing market escrow for order ${orderId}`);
}
