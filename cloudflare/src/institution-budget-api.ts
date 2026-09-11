import type { PostgresRepository } from './repository.ts';
import { canPerformInstitutionAction } from './institution-authorization.ts';

export async function getInstitutionBudget(repository: PostgresRepository, institutionId: string, gameDay?: number) {
  const result = await repository.query(`
    WITH current_period AS (
      SELECT id FROM fiscal_periods
      WHERE $2::BIGINT IS NOT NULL AND $2 BETWEEN start_game_day AND end_game_day
      ORDER BY start_game_day DESC LIMIT 1
    )
    SELECT
      p.institution_id, p.institution_kind, p.game_day,
      p.cash_treasury_units, p.cash_operations_units, p.cash_reserve_units,
      p.period_revenue_units, p.period_spending_units,
      p.budget_authorized_units, p.budget_committed_units, p.budget_spent_units,
      p.tax_receivable_units, p.arrears_units, p.mandatory_commitments_units,
      p.surplus_deficit_units, p.liquidity_days, p.financial_state,
      p.distributable_surplus_units, p.research_commitments_units,
      p.city_support_commitments_units, p.dividend_capacity_units,
      COALESCE(p.cash_treasury_units + p.cash_operations_units + p.cash_reserve_units, 0) AS cash_total_units,
      COALESCE(p.budget_authorized_units - p.budget_committed_units - p.budget_spent_units, 0) AS budget_authority_available_units
    FROM institution_financial_projections p
    WHERE p.institution_id = $1`, [institutionId, gameDay ?? null]);
  return result.rows[0] ?? null;
}

export async function listInstitutionBudgetLines(repository: PostgresRepository, institutionId: string, fiscalPeriodId?: string) {
  const result = await repository.query(`
    SELECT l.*, c.category_code, c.mandatory, c.spending_class, c.priority,
      (l.authorized_units - l.committed_units - l.spent_units) AS authority_available_units
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
