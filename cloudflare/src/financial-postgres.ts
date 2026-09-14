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
  const resolveAccount = async (ownerOrAlias: string, accountType: string): Promise<string> => {
    const result = await repository.query<{ account_id: string }>(
      `SELECT a.id::TEXT AS account_id
         FROM economic_accounts a
         JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE a.asset_id = 1
          AND a.account_type = $2
          AND a.status = 'ACTIVE'
          AND (
            o.id = $1
            OR o.id = (SELECT h.house_id FROM humans h WHERE h.id = $1)
            OR o.id = CASE
              WHEN $1 = 'account-ouc-treasury' THEN 'OUC'
              WHEN $1 = 'account-global-bank' THEN 'GLOBAL-BANK'
              ELSE $1
            END
          )
        ORDER BY a.id
        LIMIT 1`,
      [ownerOrAlias, accountType],
    );
    const accountId = result.rows[0]?.account_id;
    if (!accountId) throw new Error(`Economy V2 ${accountType} account not found for ${ownerOrAlias}`);
    return accountId;
  };
  const debitType = input.debitAccount.startsWith('account-') ? 'WALLET' : 'TREASURY';
  const creditType = input.creditAccount.startsWith('account-') ? 'TREASURY' : 'TREASURY';
  const [debitAccount, creditAccount] = await Promise.all([
    resolveAccount(input.debitAccount, debitType),
    resolveAccount(input.creditAccount, creditType),
  ]);
  const amountUnits = BigInt(Math.round(Number(input.amount) * 100));
  const result = await repository.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,$3,'INTERACTIVE',$4,$5,$6::jsonb)`,
    [input.correlationId, input.gameDay, input.reasonType, input.reasonId ?? null, input.ruleVersion, JSON.stringify([
      { account_id: debitAccount, asset_id: 1, delta_units: (-amountUnits).toString(), reason_code: input.reasonType },
      { account_id: creditAccount, asset_id: 1, delta_units: amountUnits.toString(), reason_code: input.reasonType },
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
