import type { PostgresRepository } from './repository.ts';

/**
 * Settles one game day's bank activity inside the scheduler transaction.
 * Loan interest is collected only when the corporation can actually pay it;
 * the funded remainder is then distributed across deposit entitlements.
 */
export async function settleGlobalBank(tx: PostgresRepository, day: number): Promise<number> {
  const result = await tx.query<{ loans_accrued: string; loan_payments: string }>(
    'SELECT * FROM earth_settle_v2_global_bank($1, 1439)', [day],
  );
  return Number(result.rows[0]?.loans_accrued ?? 0) + Number(result.rows[0]?.loan_payments ?? 0);
}
