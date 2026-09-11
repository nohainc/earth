import type { PostgresRepository } from './repository.ts';
import { moneyToCents, centsToMoney } from './money.ts';
export async function listBankDeposits(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const deposits = await repository.query(
    `SELECT d.id, d.principal_units, d.accrued_interest_units, d.rate_bps,
            d.rate_rule_version, d.start_total_game_minute, d.maturity_total_game_minute,
            d.status, d.created_transaction_id, d.payout_transaction_id, d.correlation_id, d.created_at
       FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
      WHERE o.id = $1 ORDER BY d.created_at DESC`,
    [humanId],
  );
  return { deposits: deposits.rows.map((row) => ({
    ...row,
    principal: centsToMoney(BigInt(String(row.principal_units))),
    accruedInterest: centsToMoney(BigInt(String(row.accrued_interest_units))),
    rateBps: row.rate_bps,
    startTotalGameMinute: row.start_total_game_minute,
    maturityTotalGameMinute: row.maturity_total_game_minute,
  })) };
}

export async function createBankDeposit(repository: PostgresRepository, input: { humanId: string; amount: number; termDays: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const id = `DEP-${input.correlationId}`;
    const result = await tx.query(
      'SELECT * FROM earth_create_v2_bank_deposit($1, $2, $3, $4, $5)',
      [id, input.humanId, moneyToCents(input.amount).toString(), input.termDays, input.correlationId],
    );
    return { ok: true, deposit: result.rows[0], alreadyProcessed: false };
  });
}

export async function withdrawBankDeposit(repository: PostgresRepository, input: { humanId: string; depositId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const result = await tx.query(
      'SELECT * FROM earth_withdraw_bank_deposit($1, $2, $3)',
      [input.humanId, input.depositId, input.correlationId],
    );
    return { ok: true, ...(result.rows[0] ?? {}) };
  });
}
