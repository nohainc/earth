import type { PostgresRepository } from './repository';
import { parseCreditAmount } from './money.ts';
import { externalTransfer } from './credit-settlement-postgres.ts';
export { resolveEconomicAccount } from './economic-account-resolver.ts';

export type CreditTransferInput = {
  ledgerId: string;
  gameDay: number;
  debitPrincipalId?: string;
  debitPurpose?: string;
  creditPrincipalId?: string;
  creditPurpose?: string;
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
  if (input.debitPrincipalId && input.debitPurpose && input.creditPrincipalId && input.creditPurpose) {
    const result = await externalTransfer(repository, {
      payer: { principalId: input.debitPrincipalId, accountPurpose: input.debitPurpose },
      beneficiary: { principalId: input.creditPrincipalId, accountPurpose: input.creditPurpose },
      amount: input.amount,
      context: { correlationId: input.correlationId, transactionKind: 'ASSET_TRANSFER', actor: { actorType: 'SYSTEM', actorId: input.reasonId ?? input.ledgerId }, purpose: input.reasonType, ruleVersion: input.ruleVersion, gameDay: input.gameDay, reasonId: input.reasonId },
    });
    return { status: result.status, ledgerId: result.transactionId, amount: result.amount, alreadyProcessed: result.status === 'already_processed' };
  }
  throw new Error('Canonical CREDIT transfers require payer and beneficiary principals with explicit account purposes');
}
