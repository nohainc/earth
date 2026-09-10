import type { PostgresRepository } from './repository';

export type CreditTransferInput = {
  ledgerId: string;
  gameDay: number;
  debitAccount: string;
  creditAccount: string;
  amount: number | string;
  reasonType: string;
  reasonId?: string | null;
  ruleVersion: string;
  correlationId: string;
};

export type CreditTransferResult = {
  status: 'applied' | 'already_processed';
  ledgerId: string;
  amount: string;
  alreadyProcessed: boolean;
};

type CreditTransferRow = {
  status: CreditTransferResult['status'];
  ledger_id: string;
  amount: string;
  already_processed: boolean;
};

/**
 * Atomic financial boundary. Policy selection stays in the caller; the
 * database owns the contested balance mutation and its audit record.
 */
export async function transferCredits(
  repository: PostgresRepository,
  input: CreditTransferInput,
): Promise<CreditTransferResult> {
  const result = await repository.query<CreditTransferRow>(
    `select * from earth_transfer_credits($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      input.ledgerId,
      input.gameDay,
      input.debitAccount,
      input.creditAccount,
      input.amount,
      input.reasonType,
      input.reasonId ?? null,
      input.ruleVersion,
      input.correlationId,
    ],
  );
  const row = result.rows[0];
  if (!row) throw new Error('Credit transfer returned no result');
  return {
    status: row.status,
    ledgerId: row.ledger_id,
    amount: row.amount,
    alreadyProcessed: row.already_processed,
  };
}

/**
 * Economy V2 adapter for ordinary CREDIT transfers. Legacy account IDs are
 * resolved through the migration map, while the legacy transfer remains a
 * compatibility fallback until every installation has completed the V2 map.
 */
export async function postEconomicCreditTransfer(
  repository: PostgresRepository,
  input: CreditTransferInput,
): Promise<CreditTransferResult> {
  const mappings = await repository.query<{ legacy_account_id: string; economic_account_id: string }>(
    `SELECT legacy_account_id, economic_account_id::TEXT
       FROM economic_account_migrations
      WHERE legacy_account_id = ANY($1::TEXT[])`,
    [[input.debitAccount, input.creditAccount]],
  );
  if (mappings.rows.length !== 2) return transferCredits(repository, input);

  const accountIds = new Map(mappings.rows.map((row) => [row.legacy_account_id, row.economic_account_id]));
  const amountUnits = BigInt(Math.round(Number(input.amount) * 100));
  const result = await repository.query<{
    transaction_id: string;
    created: boolean;
    entry_count: string;
  }>(
    `SELECT * FROM earth_post_transaction($1,$2,$3,$4,$5,$6,$7,$8::jsonb)`,
    [
      input.correlationId,
      input.gameDay,
      0,
      input.reasonType,
      'interactive',
      input.reasonId ?? null,
      input.ruleVersion,
      JSON.stringify([
        { account_id: accountIds.get(input.debitAccount), delta: (-amountUnits).toString(), reason_code: input.reasonType },
        { account_id: accountIds.get(input.creditAccount), delta: amountUnits.toString(), reason_code: input.reasonType },
      ]),
    ],
  );
  const row = result.rows[0];
  if (!row) throw new Error('V2 economic transaction returned no result');
  // Keep legacy readers and journals coherent during the transition. Both
  // postings use the same correlation ID and therefore remain retry-safe.
  await transferCredits(repository, input);
  return {
    status: row.created ? 'applied' : 'already_processed',
    ledgerId: row.transaction_id,
    amount: String(input.amount),
    alreadyProcessed: !row.created,
  };
}
