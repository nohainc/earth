import type { PostgresRepository } from './repository.ts';
import { parseCreditAmount, centsToMoney, formatCreditUnits } from './money.ts';
import { bankTransactionMetadata } from './bank-transaction-metadata.ts';
import { runEconomicMutation } from './settlement-barrier-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

function creditDisplay(units: bigint) {
  return { amountUnits: units.toString(), amount: formatCreditUnits(units), unitCode: 'CREDIT', scale: 2 };
}

export async function listBankDeposits(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const deposits = await repository.query(
    `SELECT d.id, d.principal_units, d.accrued_interest_units, d.rate_bps,
            d.maturity_total_game_minute, d.status, d.created_transaction_id,
            d.payout_transaction_id, d.correlation_id
       FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
      WHERE o.id = $1 ORDER BY d.id DESC`,
    [humanId],
  );
  return { deposits: deposits.rows.map((row) => ({
    ...row,
    principalUnits: String(row.principal_units),
    accruedInterestUnits: String(row.accrued_interest_units),
    principal: centsToMoney(BigInt(String(row.principal_units))),
    accruedInterest: centsToMoney(BigInt(String(row.accrued_interest_units))),
    principalDisplay: creditDisplay(BigInt(String(row.principal_units))),
    accruedInterestDisplay: creditDisplay(BigInt(String(row.accrued_interest_units))),
    rateBps: row.rate_bps,
    maturityTotalGameMinute: row.maturity_total_game_minute,
  })) };
}

export async function getBankDepositQuote(repository: PostgresRepository, input: { amount: string; termDays: number }): Promise<Record<string, unknown>> {
  const amountUnits = parseCreditAmount(input.amount);
  if (amountUnits <= 0n) throw new Error('Deposit amount must be positive');
  if (!Number.isInteger(input.termDays) || input.termDays <= 0) throw new Error('Deposit term must be a positive integer');
  const clock = await readAuthoritativeGameTime(repository);
  const rate = (await repository.query<{ rate_bps: string }>(
    `SELECT rate_bps::TEXT FROM bank_deposits WHERE status IN ('ACTIVE','MATURED') ORDER BY id DESC LIMIT 1`,
  )).rows[0]?.rate_bps ?? '0';
  const rateBps = BigInt(rate);
  const interestUnits = (amountUnits * rateBps * BigInt(input.termDays)) / 36500n;
  return {
    quote: {
      ...creditDisplay(amountUnits),
      requestedAmount: input.amount,
      termDays: input.termDays,
      rateBps: rateBps.toString(),
      estimatedInterestUnits: interestUnits.toString(),
      estimatedInterest: formatCreditUnits(interestUnits),
      estimatedPayoutUnits: (amountUnits + interestUnits).toString(),
      estimatedPayout: formatCreditUnits(amountUnits + interestUnits),
      maturityGameDay: clock.gameDay + input.termDays,
      pricingSource: 'postgres-bank-deposit-rate',
    },
    generatedFrom: 'postgres-canonical-bank-facts',
  };
}

export async function createBankDeposit(repository: PostgresRepository, input: { humanId: string; amount: string | number | bigint; termDays: number; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const id = `DEP-${input.correlationId}`;
    const result = await tx.query(
      'SELECT * FROM earth_create_v2_bank_deposit($1, $2, $3, $4, $5)',
      [id, input.humanId, typeof input.amount === 'bigint' ? input.amount.toString() : parseCreditAmount(input.amount).toString(), input.termDays, input.correlationId],
    );
    const deposit = result.rows[0]?.principal_units != null
      ? result.rows[0]
      : (await tx.query(`SELECT id, principal_units::TEXT, accrued_interest_units::TEXT, rate_bps, maturity_total_game_minute, status FROM bank_deposits WHERE correlation_id = $1`, [input.correlationId])).rows[0] ?? result.rows[0] ?? {};
    const principalUnits = BigInt(String(deposit.principal_units ?? deposit.amount_units ?? 0));
    return { ok: true, deposit: { ...deposit, principalUnits: principalUnits.toString(), principal: formatCreditUnits(principalUnits), principalDisplay: creditDisplay(principalUnits) }, transactionMetadata: bankTransactionMetadata('BANK_DEPOSIT_FUNDING', id, 'BANK_DEPOSIT_FUNDING'), alreadyProcessed: false };
  });
}

export async function withdrawBankDeposit(repository: PostgresRepository, input: { humanId: string; depositId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const result = await tx.query(
      'SELECT * FROM earth_withdraw_bank_deposit($1, $2, $3)',
      [input.humanId, input.depositId, input.correlationId],
    );
    return { ok: true, ...(result.rows[0] ?? {}), transactionMetadata: bankTransactionMetadata('BANK_DEPOSIT_PAYOUT', input.depositId, 'BANK_DEPOSIT_PAYOUT') };
  });
}
