import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents, rateAmountToCents } from './money.ts';

const BANK_ACCOUNT = 'account-global-corporate-bank';
const RESERVE_SHARE_MICROS = 200_000n; // 20% of realized loan income.
const RATE_SCALE = 1_000_000n;

type DepositRow = {
  id: string;
  principal: string;
  daily_rate: string;
  maturity_game_day: number;
  last_settled_game_day: number;
};

function elapsedDepositDays(deposit: DepositRow, day: number): number {
  const endDay = Math.min(day, Number(deposit.maturity_game_day));
  return Math.max(0, endDay - Number(deposit.last_settled_game_day));
}

/**
 * Settles one game day's bank activity inside the scheduler transaction.
 * Loan interest is collected only when the corporation can actually pay it;
 * the funded remainder is then distributed across deposit entitlements.
 */
export async function settleGlobalBank(tx: PostgresRepository, day: number): Promise<number> {
  const journal = await tx.query('SELECT 1 FROM global_bank_settlement_journals WHERE game_day = $1', [day]);
  if (journal.rows[0]) return 0;

  const bank = await tx.query<{ account_id: string }>(
    "SELECT account_id FROM account_balances WHERE account_id = $1 AND currency = 'CREDIT' FOR UPDATE",
    [BANK_ACCOUNT],
  );
  if (!bank.rows[0]) throw new Error('Global bank account is unavailable; apply the bank migration first');

  let loanIncomeCents = 0n;
  const loans = await tx.query<{
    id: string;
    corporation_id: string;
    outstanding_principal: string;
    daily_rate: string;
  }>("SELECT id, corporation_id, outstanding_principal, daily_rate FROM global_bank_loans WHERE status = 'active' AND outstanding_principal > 0 FOR UPDATE");

  for (const loan of loans.rows) {
    const incomeCents = rateAmountToCents(moneyToCents(loan.outstanding_principal), loan.daily_rate, 1);
    if (incomeCents <= 0n) continue;
    const corporationAccount = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [loan.corporation_id],
    );
    if (!corporationAccount.rows[0] || moneyToCents(corporationAccount.rows[0].balance) < incomeCents) continue;

    await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: corporationAccount.rows[0].account_id,
      creditAccount: BANK_ACCOUNT,
      amount: centsToMoney(incomeCents),
      reasonType: 'global_bank_loan_interest',
      reasonId: loan.id,
      ruleVersion: 'global-bank-v1',
      correlationId: `GLOBAL-BANK-LOAN-${loan.id}-${day}`,
    });
    loanIncomeCents += incomeCents;
  }

  const reserveCents = (loanIncomeCents * RESERVE_SHARE_MICROS + RATE_SCALE / 2n) / RATE_SCALE;
  const interestPoolCents = loanIncomeCents - reserveCents;
  const deposits = await tx.query<DepositRow>(
    "SELECT id, principal, daily_rate, maturity_game_day, last_settled_game_day FROM global_bank_deposits WHERE status IN ('active', 'matured') AND last_settled_game_day < LEAST($1, maturity_game_day) FOR UPDATE",
    [day],
  );

  const entitlements = deposits.rows.map((deposit) => ({
    deposit,
    days: elapsedDepositDays(deposit, day),
    dailyCents: rateAmountToCents(moneyToCents(deposit.principal), deposit.daily_rate, 1),
  })).map((item) => ({ ...item, requestedCents: item.dailyCents * BigInt(item.days) }));
  const totalRequestedCents = entitlements.reduce((sum, item) => sum + item.requestedCents, 0n);
  const fundedInterestCents = interestPoolCents < totalRequestedCents ? interestPoolCents : totalRequestedCents;
  let allocatedCents = 0n;

  for (const [index, item] of entitlements.entries()) {
    const allocation = totalRequestedCents <= 0n
      ? 0n
      : index === entitlements.length - 1
        ? fundedInterestCents - allocatedCents
        : (fundedInterestCents * item.requestedCents) / totalRequestedCents;
    allocatedCents += allocation;
    await tx.query(
      `UPDATE global_bank_deposits
          SET accrued_interest = accrued_interest + $1,
              last_settled_game_day = CASE WHEN $1 > 0 THEN $2 ELSE last_settled_game_day END,
              status = CASE WHEN maturity_game_day <= $2 AND status = 'active' THEN 'matured' ELSE status END,
              updated_at = CURRENT_TIMESTAMP
        WHERE id = $3`,
      [centsToMoney(allocation), day, item.deposit.id],
    );
  }

  await tx.query(
    `UPDATE global_bank_deposits
        SET status = 'matured', updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active' AND maturity_game_day <= $1`,
    [day],
  );
  await tx.query(
    `INSERT INTO global_bank_settlement_journals
      (id, game_day, loan_income, operating_costs, reserve_contribution, interest_pool, interest_paid)
     VALUES ($1, $2, $3, 0, $4, $5, $6)`,
    [crypto.randomUUID(), day, centsToMoney(loanIncomeCents), centsToMoney(reserveCents), centsToMoney(interestPoolCents), centsToMoney(allocatedCents)],
  );

  return loans.rows.length;
}
