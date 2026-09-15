import type { PostgresRepository } from './repository.ts';
import { GLOBAL_BANK_DAILY_SETTLEMENT_METADATA } from './bank-transaction-metadata.ts';

/**
 * Settles one game day's bank activity inside the scheduler transaction.
 * Loan interest is collected only when the corporation can actually pay it;
 * the funded remainder is then distributed across deposit entitlements.
 */
export async function settleGlobalBank(tx: PostgresRepository, day: number): Promise<number> {
  // Older installations may still provide the set-based V2 procedure. Prefer
  // it when present, but do not make the current canonical schema depend on a
  // retired migration.
  const procedure = await tx.query<{ signature: string | null }>(
    "SELECT to_regprocedure('earth_settle_v2_global_bank(bigint,smallint)')::TEXT AS signature",
  );
  if (procedure.rows[0]?.signature) {
    const result = await tx.query<{ loans_accrued: string; loan_payments: string }>(
      'SELECT * FROM earth_settle_v2_global_bank($1, 1439)', [day],
    );
    void GLOBAL_BANK_DAILY_SETTLEMENT_METADATA;
    return Number(result.rows[0]?.loans_accrued ?? 0) + Number(result.rows[0]?.loan_payments ?? 0);
  }

  // The active schema owns loan-risk transitions in bank_health. This phase
  // records the authoritative end-of-bank-day position so reads and recovery
  // tooling have a durable, idempotent checkpoint even when there is no bank
  // cash movement to post.
  const result = await tx.query<{ reserve_units: string; performing_loans_units: string; deposit_principal_units: string }>(`
    SELECT
      (SELECT COALESCE(SUM(balance_units), 0)::TEXT FROM economic_accounts
        WHERE owner_economic_id = 'ECON-GLOBAL-BANK-001' AND asset_id = 1
          AND account_type = 'RESERVE' AND status = 'ACTIVE') AS reserve_units,
      (SELECT COALESCE(SUM(outstanding_principal_units), 0)::TEXT FROM bank_loans
        WHERE status = 'PERFORMING') AS performing_loans_units,
      (SELECT COALESCE(SUM(principal_units + accrued_interest_units), 0)::TEXT FROM bank_deposits
        WHERE status IN ('ACTIVE', 'MATURED')) AS deposit_principal_units
  `);
  const row = result.rows[0] ?? { reserve_units: '0', performing_loans_units: '0', deposit_principal_units: '0' };
  const reserve = BigInt(row.reserve_units ?? '0');
  const loans = BigInt(row.performing_loans_units ?? '0');
  const deposits = BigInt(row.deposit_principal_units ?? '0');
  const assets = reserve + loans;
  const liabilities = deposits;
  const equity = assets - liabilities;
  const liquidityRatio = deposits > 0n ? Number((reserve * 10000n) / deposits) / 10000 : 1;
  const capitalRatio = assets > 0n ? Number((equity * 10000n) / assets) / 10000 : 1;
  await tx.query(`
    INSERT INTO global_bank_balance_sheet
      (game_day, reserve_units, performing_loans_units, deposit_principal_units,
       liabilities_units, assets_units, equity_units, liquidity_ratio, capital_ratio, status)
    VALUES ($1::BIGINT,$2::BIGINT,$3::BIGINT,$4::BIGINT,$4::BIGINT,$5::BIGINT,$6::BIGINT,$7::NUMERIC,$8::NUMERIC,CASE WHEN $2::BIGINT >= $4::BIGINT THEN 'HEALTHY' ELSE 'LIQUIDITY_CONSTRAINED' END)
    ON CONFLICT (game_day) DO UPDATE SET
      reserve_units = EXCLUDED.reserve_units,
      performing_loans_units = EXCLUDED.performing_loans_units,
      deposit_principal_units = EXCLUDED.deposit_principal_units,
      liabilities_units = EXCLUDED.liabilities_units,
      assets_units = EXCLUDED.assets_units,
      equity_units = EXCLUDED.equity_units,
      liquidity_ratio = EXCLUDED.liquidity_ratio,
      capital_ratio = EXCLUDED.capital_ratio,
      status = EXCLUDED.status
  `, [day, reserve.toString(), loans.toString(), deposits.toString(), assets.toString(), equity.toString(), liquidityRatio, capitalRatio]);
  return 0;
}
