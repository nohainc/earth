import type { PostgresRepository } from './repository.ts';

export type InstitutionalSpendingInput = {
  institutionId: string;
  budgetLineId: string;
  sourceAccountId: string;
  recipientAccountId: string;
  amountUnits: bigint;
  purpose: string;
  sourceType: string;
  sourceId: string;
  correlationId: string;
  gameDay: number;
  commitmentId?: string;
  restrictionId?: string;
};

export async function spendInstitutionBudget(
  tx: PostgresRepository,
  input: InstitutionalSpendingInput,
): Promise<{ transactionId: string; journalId: string; commitmentId: string | null; alreadyProcessed: boolean }> {
  const prior = await tx.query<{ id: string; economic_transaction_id: string; commitment_id: string | null }>(
    'SELECT id, economic_transaction_id, commitment_id FROM institution_spending_journals WHERE correlation_id = $1',
    [input.correlationId],
  );
  if (prior.rows[0]) return { transactionId: prior.rows[0].economic_transaction_id, journalId: prior.rows[0].id, commitmentId: prior.rows[0].commitment_id, alreadyProcessed: true };
  if (input.amountUnits <= 0n) throw new Error('Institutional spending amount must be positive');

  const line = await tx.query<{ institution_id: string; authorized_units: string; committed_units: string; spent_units: string; spending_class: string; status: string }>(
    'SELECT b.institution_id, b.authorized_units, b.committed_units, b.spent_units, b.status, c.spending_class FROM institution_budget_lines b JOIN budget_categories c ON c.id = b.category_id WHERE b.id = $1 FOR UPDATE',
    [input.budgetLineId],
  );
  if (!line.rows[0] || line.rows[0].institution_id !== input.institutionId) throw new Error('Budget line does not belong to institution');
  if (!['ACTIVE'].includes(line.rows[0].status)) throw new Error(`Budget line is ${line.rows[0].status.toLowerCase()} and cannot be spent`);
  const financialState = await tx.query<{ status: string }>('SELECT status FROM financial_states WHERE institution_id = $1', [input.institutionId]);
  if (['FISCAL_STRESS', 'RECEIVERSHIP', 'fiscal_stress', 'receivership'].includes(financialState.rows[0]?.status ?? '') && line.rows[0].spending_class === 'DISCRETIONARY') {
    throw new Error('Discretionary spending is frozen during financial stress');
  }

  const source = await tx.query<{ balance: string }>('SELECT balance::TEXT AS balance FROM economic_accounts WHERE id = $1 AND status = \'active\' FOR UPDATE', [input.sourceAccountId]);
  if (!source.rows[0]) throw new Error('Institution source account is unavailable');
  if (BigInt(source.rows[0].balance) < input.amountUnits) throw new Error('Institution source account cannot fund this spending');

  if (input.commitmentId) {
    const commitment = await tx.query<{ remaining_units: string; budget_line_id: string; status: string }>(
      'SELECT remaining_units, budget_line_id, status FROM institution_budget_commitments WHERE id = $1 FOR UPDATE',
      [input.commitmentId],
    );
    if (!commitment.rows[0] || commitment.rows[0].budget_line_id !== input.budgetLineId || !['ACTIVE', 'PARTIALLY_PAID'].includes(commitment.rows[0].status)) throw new Error('Budget commitment is not payable');
    if (BigInt(commitment.rows[0].remaining_units) < input.amountUnits) throw new Error('Spending exceeds remaining commitment');
  } else if (BigInt(line.rows[0].authorized_units) - BigInt(line.rows[0].committed_units) - BigInt(line.rows[0].spent_units) < input.amountUnits) {
    throw new Error('Spending exceeds available budget authority');
  }
  if (input.restrictionId) {
    const restriction = await tx.query<{ remaining_units: string; recipient_institution_id: string; budget_line_id: string; status: string }>(
      'SELECT remaining_units, recipient_institution_id, budget_line_id, status FROM grant_restrictions WHERE id = $1 FOR UPDATE',
      [input.restrictionId],
    );
    if (!restriction.rows[0] || restriction.rows[0].status !== 'ACTIVE' || restriction.rows[0].recipient_institution_id !== input.institutionId || restriction.rows[0].budget_line_id !== input.budgetLineId) throw new Error('Grant restriction does not apply to this budget line');
    if (BigInt(restriction.rows[0].remaining_units) < input.amountUnits) throw new Error('Spending exceeds restricted grant authority');
  }
  // A corporation allocation is an optional authority ceiling for a city. It
  // does not select or fund the source account; the caller's explicit source
  // account remains authoritative (normally the city's own treasury).
  const allocation = await tx.query<{ allocation_units: string; allocation_count: string }>(
    `SELECT COALESCE(SUM(authorized_units), 0)::TEXT AS allocation_units, COUNT(*)::TEXT AS allocation_count
       FROM institution_budget_allocations
      WHERE child_budget_line_id = $1 AND status IN ('DRAFT', 'ACTIVE')`,
    [input.budgetLineId],
  );
  if (Number(allocation.rows[0]?.allocation_count ?? '0') > 0) {
    const allocated = BigInt(allocation.rows[0].allocation_units);
    const used = BigInt(line.rows[0].committed_units) + BigInt(line.rows[0].spent_units) + input.amountUnits;
    if (used > allocated) throw new Error('Spending exceeds the corporation allocation ceiling');
  }

  const posting = await tx.query<{ transaction_id: string; created: boolean }>(
    `SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,$3,$4,$5,$6,$7::jsonb)`,
    [input.correlationId, input.gameDay, input.purpose, input.sourceType, input.sourceId, 'institution-budget-v2', JSON.stringify([
      { account_id: input.sourceAccountId, delta: (-input.amountUnits).toString(), reason_code: input.purpose },
      { account_id: input.recipientAccountId, delta: input.amountUnits.toString(), reason_code: input.purpose },
    ])],
  );
  const postingRow = posting.rows[0];
  if (!postingRow) throw new Error('Economy V2 posting returned no transaction');
  if (input.commitmentId) {
    await tx.query('SELECT * FROM earth_pay_budget_commitment($1,$2)', [input.commitmentId, input.amountUnits]);
  } else {
    await tx.query('UPDATE institution_budget_lines SET spent_units = spent_units + $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [input.amountUnits, input.budgetLineId]);
  }
  if (input.restrictionId) {
    await tx.query(`UPDATE grant_restrictions SET remaining_units = remaining_units - $1,
      status = CASE WHEN remaining_units - $1 = 0 THEN 'EXHAUSTED' ELSE 'ACTIVE' END,
      updated_at = CURRENT_TIMESTAMP WHERE id = $2`, [input.amountUnits, input.restrictionId]);
  }
  const journal = await tx.query<{ id: string }>(
    `INSERT INTO institution_spending_journals
      (institution_id, budget_line_id, commitment_id, source_account_id, recipient_account_id, amount_units, purpose, source_type, source_id, economic_transaction_id, correlation_id, game_day)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     RETURNING id`,
    [input.institutionId, input.budgetLineId, input.commitmentId ?? null, input.sourceAccountId, input.recipientAccountId, input.amountUnits, input.purpose, input.sourceType, input.sourceId, postingRow.transaction_id, input.correlationId, input.gameDay],
  );
  await tx.query(`SELECT earth_record_institution_financial_event($1,$2,'SPENDING',$3,$4,$5::bigint,$6,NULL,NULL,$7)`, [input.institutionId, input.gameDay, input.amountUnits, input.budgetLineId, postingRow.transaction_id, input.sourceId, input.correlationId]);
  return { transactionId: postingRow.transaction_id, journalId: journal.rows[0].id, commitmentId: input.commitmentId ?? null, alreadyProcessed: !postingRow.created };
}

// Short domain name used by proposal/project execution code.
export const spendBudget = spendInstitutionBudget;
