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
