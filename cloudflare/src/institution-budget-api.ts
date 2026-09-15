import type { PostgresRepository } from './repository.ts';
import { canPerformInstitutionAction } from './institution-authorization.ts';
import { getInstitutionFinancialProjection } from './financial-projections.ts';

export async function getInstitutionBudget(repository: PostgresRepository, institutionId: string, _gameDay?: number) {
  const projection = await getInstitutionFinancialProjection(repository, institutionId);
  const [obligations, state] = await Promise.all([
    repository.query<{ receivable_units: string; arrears_units: string }>(
      `SELECT COALESCE(SUM(CASE WHEN status IN ('DUE','PARTIAL') THEN principal_due_units + interest_due_units - paid_units ELSE 0 END), 0)::TEXT AS receivable_units,
              COALESCE(SUM(CASE WHEN status = 'ARREARS' THEN principal_due_units + interest_due_units - paid_units ELSE 0 END), 0)::TEXT AS arrears_units
         FROM financial_obligations WHERE creditor_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)`, [institutionId]),
    repository.query<{ financial_state: string }>('SELECT status AS financial_state FROM organization_financial_states WHERE organization_id = $1', [institutionId]),
  ]);
  const budgetAuthorized = String(projection.authorizedUnits ?? '0');
  const budgetCommitted = String(projection.committedUnits ?? '0');
  const budgetSpent = String(projection.spentUnits ?? '0');
  const cashTotal = [projection.treasuryUnits, projection.operationsUnits, projection.reserveUnits]
    .reduce((sum, value) => sum + BigInt(String(value ?? '0')), 0n).toString();
  return {
    institution_id: institutionId,
    institution_kind: projection.scope,
    game_day: _gameDay ?? null,
    cash_treasury_units: projection.treasuryUnits,
    cash_operations_units: projection.operationsUnits,
    cash_reserve_units: projection.reserveUnits,
    period_revenue_units: projection.revenueUnits,
    period_spending_units: projection.expenseUnits,
    budget_authorized_units: budgetAuthorized,
    budget_committed_units: budgetCommitted,
    budget_spent_units: budgetSpent,
    tax_receivable_units: obligations.rows[0]?.receivable_units ?? '0',
    arrears_units: obligations.rows[0]?.arrears_units ?? '0',
    cash_total_units: cashTotal,
    available_authority: projection.availableUnits,
    budget_authority_available_units: projection.availableUnits,
    available_cash: cashTotal,
    committed: budgetCommitted,
    spent: budgetSpent,
    financial_state: state.rows[0]?.financial_state ?? null,
    generated_from: 'postgres-canonical-facts',
  };
}

export async function listInstitutionBudgetLines(repository: PostgresRepository, institutionId: string, fiscalPeriodId?: string) {
  const result = await repository.query(`
    SELECT l.*, c.category_code, c.mandatory, c.spending_class, c.priority,
      (l.authorized_units - l.committed_units - l.spent_units) AS available_authority,
      (l.committed_units) AS committed, (l.spent_units) AS spent,
      COALESCE((SELECT SUM(a.balance_units) FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                 WHERE o.id = l.institution_id AND a.asset_id = 1 AND a.account_type IN ('TREASURY','OPERATIONS','RESERVE') AND a.status = 'ACTIVE'), 0) AS available_cash
    FROM institution_budget_lines l JOIN budget_categories c ON c.id = l.category_id
    WHERE l.institution_id = $1 AND ($2::BIGINT IS NULL OR l.fiscal_period_id = $2)
    ORDER BY l.fiscal_period_id DESC, c.priority, c.category_code`, [institutionId, fiscalPeriodId ?? null]);
  return result.rows;
}

export async function listInstitutionCommitments(repository: PostgresRepository, institutionId: string, fiscalPeriodId?: string) {
  const result = await repository.query(`
    SELECT c.*, l.fiscal_period_id, l.category_id, bc.category_code, bc.mandatory, bc.spending_class,
      (c.remaining_units > 0) AS outstanding
    FROM institution_budget_commitments c
    JOIN institution_budget_lines l ON l.id = c.budget_line_id
    JOIN budget_categories bc ON bc.id = l.category_id
    WHERE c.institution_id = $1 AND ($2::BIGINT IS NULL OR l.fiscal_period_id = $2)
    ORDER BY c.due_game_day, c.priority_class, c.id`, [institutionId, fiscalPeriodId ?? null]);
  return result.rows;
}

export async function createInstitutionCommitment(tx: PostgresRepository, input: {
  humanId: string; institutionId: string; budgetLineId: string; commitmentType: string;
  sourceType: string; sourceId: string; amountUnits: bigint; gameDay: number; dueGameDay: number;
}) {
  if (!(await canPerformInstitutionAction(tx, input.humanId, input.institutionId, 'CREATE_COMMITMENT', input.gameDay))) throw new Error('Institution commitment permission is required');
  if (input.amountUnits <= 0n || input.dueGameDay < input.gameDay) throw new Error('Invalid commitment amount or due day');
  const result = await tx.query<{ id: string }>(
    'SELECT earth_create_budget_commitment($1,$2,$3,$4,$5,$6,$7,$8) AS id',
    [input.institutionId, input.budgetLineId, input.commitmentType, input.sourceType, input.sourceId, input.amountUnits, input.gameDay, input.dueGameDay],
  );
  return result.rows[0]?.id ?? null;
}

export async function payInstitutionCommitment(tx: PostgresRepository, input: { humanId: string; institutionId: string; commitmentId: string; amountUnits: bigint; gameDay: number }) {
  if (!(await canPerformInstitutionAction(tx, input.humanId, input.institutionId, 'APPROVE_SPENDING', input.gameDay))) throw new Error('Institution spending permission is required');
  const owner = await tx.query<{ institution_id: string }>('SELECT institution_id FROM institution_budget_commitments WHERE id = $1 FOR UPDATE', [input.commitmentId]);
  if (!owner.rows[0] || owner.rows[0].institution_id !== input.institutionId) throw new Error('Commitment does not belong to institution');
  const result = await tx.query('SELECT * FROM earth_pay_budget_commitment($1,$2)', [input.commitmentId, input.amountUnits]);
  return result.rows[0] ?? null;
}

export async function cancelInstitutionCommitment(tx: PostgresRepository, input: { humanId: string; institutionId: string; commitmentId: string; gameDay: number }) {
  if (!(await canPerformInstitutionAction(tx, input.humanId, input.institutionId, 'CREATE_COMMITMENT', input.gameDay))) throw new Error('Institution commitment permission is required');
  const owner = await tx.query<{ institution_id: string }>('SELECT institution_id FROM institution_budget_commitments WHERE id = $1 FOR UPDATE', [input.commitmentId]);
  if (!owner.rows[0] || owner.rows[0].institution_id !== input.institutionId) throw new Error('Commitment does not belong to institution');
  return tx.query('SELECT earth_cancel_budget_commitment($1) AS released_units', [input.commitmentId]).then((result) => result.rows[0] ?? null);
}
