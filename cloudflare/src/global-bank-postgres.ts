import type { PostgresRepository } from './repository.ts';
export async function listBankDeposits(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const deposits = await repository.query(
    `SELECT id, principal, daily_rate, accrued_interest, start_game_day, start_game_minute,
            maturity_game_day, maturity_game_minute,
            last_settled_game_day, status, created_at
       FROM global_bank_deposits WHERE human_id = $1 ORDER BY created_at DESC`,
    [humanId],
  );
  return { deposits: deposits.rows };
}

export async function createBankDeposit(repository: PostgresRepository, input: { humanId: string; amount: number; termDays: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const id = `DEP-${input.correlationId}`;
    const result = await tx.query(
      'SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)',
      [id, input.humanId, input.amount, input.termDays, input.correlationId],
    );
    return { ok: true, deposit: result.rows[0] };
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
