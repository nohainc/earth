import type { PostgresRepository } from './repository.ts';
import { formatCreditUnits, parseCreditAmount, type CreditUnits } from './money.ts';
import { resolveEconomicAccount } from './economic-account-resolver.ts';
import { runEconomicMutation, postEconomicTransaction, type EconomicMutationContext } from './settlement-barrier-postgres.ts';

export type CreditActorContext = { actorType: 'HUMAN' | 'SYSTEM'; actorId: string };
export type CreditPrincipalContext = { principalId: string; accountPurpose: string };
export type CreditSettlementContext = {
  correlationId: string;
  transactionKind: 'ASSET_TRANSFER' | 'CREDIT_ISSUANCE' | 'CREDIT_RETIREMENT';
  actor: CreditActorContext;
  purpose: string;
  ruleVersion: string;
  gameDay: number;
  gameMinute?: number;
  reasonId?: string | null;
};
export type CreditTransferResult = { status: 'applied' | 'already_processed'; transactionId: string; amountUnits: CreditUnits; amount: string };

async function postCreditEntries(tx: PostgresRepository, context: CreditSettlementContext, debitAccountId: string, creditAccountId: string, amountUnits: CreditUnits, gameTime: EconomicMutationContext): Promise<CreditTransferResult> {
  if (amountUnits <= 0n) throw new Error('CREDIT settlement amount must be positive');
  const result = await postEconomicTransaction(tx, {
    correlationId: context.correlationId,
    kind: context.transactionKind,
    sourceType: context.actor.actorType === 'SYSTEM' ? 'SYSTEM_SETTLEMENT' : 'HUMAN_ACTION',
    sourceId: context.reasonId ?? context.actor.actorId,
    rulesVersion: context.ruleVersion,
    entries: [
      { account_id: debitAccountId, asset_id: 1, delta_units: (-amountUnits).toString(), reason_code: context.purpose },
      { account_id: creditAccountId, asset_id: 1, delta_units: amountUnits.toString(), reason_code: context.purpose },
    ],
  }, gameTime);
  return { status: result.created ? 'applied' : 'already_processed', transactionId: result.transactionId, amountUnits, amount: formatCreditUnits(amountUnits) };
}

export async function externalTransfer(repository: PostgresRepository, input: { payer: CreditPrincipalContext; beneficiary: CreditPrincipalContext; amount: string | number | bigint; context: CreditSettlementContext }): Promise<CreditTransferResult> {
  return runEconomicMutation(repository, async (tx, clock) => postCreditEntries(tx, input.context, await resolveEconomicAccount(tx, input.payer.principalId, input.payer.accountPurpose), await resolveEconomicAccount(tx, input.beneficiary.principalId, input.beneficiary.accountPurpose), parseCreditAmount(input.amount), clock));
}

export async function internalTransfer(repository: PostgresRepository, input: { principalId: string; debitPurpose: string; creditPurpose: string; amount: string | number | bigint; context: CreditSettlementContext }): Promise<CreditTransferResult> {
  return runEconomicMutation(repository, async (tx, clock) => postCreditEntries(tx, input.context, await resolveEconomicAccount(tx, input.principalId, input.debitPurpose), await resolveEconomicAccount(tx, input.principalId, input.creditPurpose), parseCreditAmount(input.amount), clock));
}

export async function reserve(repository: PostgresRepository, input: { principalId: string; sourcePurpose: string; amount: string | number | bigint; context: CreditSettlementContext }): Promise<CreditTransferResult> {
  return internalTransfer(repository, { principalId: input.principalId, debitPurpose: input.sourcePurpose, creditPurpose: 'MARKET_ESCROW', amount: input.amount, context: { ...input.context, transactionKind: 'ASSET_TRANSFER', purpose: 'CREDIT_RESERVATION' } });
}

export async function release(repository: PostgresRepository, input: { principalId: string; sourcePurpose: 'MARKET_ESCROW'; targetPurpose: string; amount: string | number | bigint; context: CreditSettlementContext }): Promise<CreditTransferResult> {
  return internalTransfer(repository, { principalId: input.principalId, debitPurpose: input.sourcePurpose, creditPurpose: input.targetPurpose, amount: input.amount, context: { ...input.context, transactionKind: 'ASSET_TRANSFER', purpose: 'CREDIT_RELEASE' } });
}

export async function settleObligation(repository: PostgresRepository, input: { obligationId: string; context: CreditSettlementContext }): Promise<CreditTransferResult> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const obligation = await tx.query<{ debtor_economic_id: string; creditor_economic_id: string; principal_due_units: string; interest_due_units: string; paid_units: string; debtor_account_purpose: string; creditor_account_purpose: string; status: string; obligation_type: string; source_id: string | null }>(
      `SELECT debtor_economic_id, creditor_economic_id, principal_due_units::TEXT, interest_due_units::TEXT, paid_units::TEXT, debtor_account_purpose, creditor_account_purpose, status, obligation_type, source_id FROM financial_obligations WHERE id=$1 FOR UPDATE`, [input.obligationId]);
    const row = obligation.rows[0];
    if (!row) throw new Error('CREDIT obligation not found');
    if (row.obligation_type === 'SERVICE_INVOICE' && row.source_id) {
      const performance = (await tx.query<{ status: string }>('SELECT status FROM contract_performance_events WHERE obligation_id = $1 FOR UPDATE', [input.obligationId])).rows[0];
      if (performance && performance.status !== 'ACCEPTED') {
        if (['FAILED', 'WAIVED'].includes(performance.status)) {
          await tx.query("UPDATE financial_obligations SET status = 'CANCELLED', cancelled_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1", [input.obligationId, input.context.gameDay]);
        } else {
          await tx.query('UPDATE financial_obligations SET due_game_day = GREATEST(due_game_day, $2 + 1), updated_at = CURRENT_TIMESTAMP WHERE id = $1', [input.obligationId, input.context.gameDay]);
        }
        return { status: 'already_processed', transactionId: 'delivery-pending', amountUnits: 0n, amount: formatCreditUnits(0n) };
      }
    }
    const remaining = BigInt(row.principal_due_units) + BigInt(row.interest_due_units) - BigInt(row.paid_units);
    if (row.status === 'CANCELLED' || remaining <= 0n) return { status: 'already_processed', transactionId: 'already-paid', amountUnits: 0n, amount: formatCreditUnits(0n) };
    const payment = await postCreditEntries(tx, { ...input.context, transactionKind: 'ASSET_TRANSFER', purpose: 'OBLIGATION_PAYMENT', reasonId: input.obligationId }, await resolveEconomicAccount(tx, row.debtor_economic_id, row.debtor_account_purpose), await resolveEconomicAccount(tx, row.creditor_economic_id, row.creditor_account_purpose), remaining, clock);
    await tx.query(`UPDATE financial_obligations SET paid_units=paid_units+$2, status=CASE WHEN paid_units+$2 >= principal_due_units+interest_due_units THEN 'PAID' ELSE 'PARTIAL' END, payment_transaction_id=$3, updated_at=CURRENT_TIMESTAMP WHERE id=$1`, [input.obligationId, remaining, payment.transactionId]);
    return payment;
  });
}

export async function createFinancialObligation(repository: PostgresRepository, input: { id: string; debtorPrincipalId: string; creditorPrincipalId: string; obligationType: 'TAX' | 'ROYALTY' | 'LICENSE_PAYMENT' | 'LOAN_PAYMENT' | 'SERVICE_INVOICE' | 'FINE_FEE'; sourceId?: string | null; principalDue: string | number | bigint; interestDue?: string | number | bigint; debtorAccountPurpose?: string; creditorAccountPurpose?: string; dueGameDay: number; ruleVersion: string; createdGameDay: number; correlationId: string }): Promise<string> {
  const principal = parseCreditAmount(input.principalDue);
  const interest = parseCreditAmount(input.interestDue ?? 0);
  if (principal < 0n || interest < 0n || input.dueGameDay < input.createdGameDay) throw new Error('Invalid CREDIT obligation');
  return repository.query<{ id: string }>(
    `INSERT INTO financial_obligations (id,debtor_economic_id,creditor_economic_id,obligation_type,source_id,principal_due_units,interest_due_units,debtor_account_purpose,creditor_account_purpose,due_game_day,rule_version,created_game_day,correlation_id)
     SELECT $1,d.economic_id,c.economic_id,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13 FROM owner_registry d,owner_registry c WHERE d.id=$2 AND c.id=$3 RETURNING id`,
    [input.id, input.debtorPrincipalId, input.creditorPrincipalId, input.obligationType, input.sourceId ?? null, principal.toString(), interest.toString(), input.debtorAccountPurpose ?? 'WALLET', input.creditorAccountPurpose ?? 'TREASURY', input.dueGameDay, input.ruleVersion, input.createdGameDay, input.correlationId],
  ).then((result) => { if (!result.rows[0]) throw new Error('Obligation principals were not found'); return result.rows[0].id; });
}

export async function cancelFinancialObligation(repository: PostgresRepository, obligationId: string, gameDay: number): Promise<void> {
  await repository.query(`UPDATE financial_obligations SET status='CANCELLED', cancelled_game_day=$2, updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND status IN ('DUE','PARTIAL','ARREARS')`, [obligationId, gameDay]);
}

export async function markFinancialObligationsInArrears(repository: PostgresRepository, gameDay: number): Promise<number> {
  const result = await repository.query<{ count: string }>(`WITH updated AS (UPDATE financial_obligations SET status='ARREARS', updated_at=CURRENT_TIMESTAMP WHERE due_game_day<$1 AND status IN ('DUE','PARTIAL') RETURNING 1) SELECT COUNT(*)::TEXT count FROM updated`, [gameDay]);
  return Number(result.rows[0]?.count ?? 0);
}
