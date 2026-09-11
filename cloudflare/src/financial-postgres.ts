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

/**
 * Atomic financial boundary. Policy selection stays in the caller; the
 * database owns the contested balance mutation and its audit record.
 */
export async function transferCredits(
  repository: PostgresRepository,
  input: CreditTransferInput,
): Promise<CreditTransferResult> {
  const mappings = await repository.query<{ legacy_account_id: string; economic_account_id: string }>(
    `SELECT legacy_account_id, economic_account_id::TEXT FROM economic_account_migrations WHERE legacy_account_id = ANY($1::TEXT[])`,
    [[input.debitAccount, input.creditAccount]],
  );
  if (mappings.rows.length !== 2) throw new Error('Economy V2 account mapping is required for every credit transfer');
  const accountIds = new Map(mappings.rows.map((row) => [row.legacy_account_id, row.economic_account_id]));
  const amountUnits = BigInt(Math.round(Number(input.amount) * 100));
  const result = await repository.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,$3,'interactive',$4,$5,$6::jsonb)`,
    [input.correlationId, input.gameDay, input.reasonType, input.reasonId ?? null, input.ruleVersion, JSON.stringify([
      { account_id: accountIds.get(input.debitAccount), delta: (-amountUnits).toString(), reason_code: input.reasonType },
      { account_id: accountIds.get(input.creditAccount), delta: amountUnits.toString(), reason_code: input.reasonType },
    ])],
  );
  const row = result.rows[0];
  if (!row) throw new Error('V2 economic transaction returned no result');
  return {
    status: row.created ? 'applied' : 'already_processed',
    ledgerId: row.transaction_id,
    amount: String(input.amount),
    alreadyProcessed: !row.created,
  };
}

/**
 * Compatibility-named adapter retained for callers while all postings use V2.
 */
export async function postEconomicCreditTransfer(
  repository: PostgresRepository,
  input: CreditTransferInput,
): Promise<CreditTransferResult> {
  return transferCredits(repository, input);
}
