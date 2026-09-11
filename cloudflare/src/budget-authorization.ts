import type { PostgresRepository } from './repository.ts';

export type BudgetAuthorizationInput = {
  institutionId: string;
  institutionKind: string;
  fiscalPeriodId: string;
  categoryCode: string;
  authorizedUnits: bigint;
  createdGameDay: number;
  ruleVersion: string;
};

/** Changes spending authority only. It never moves money or marks spending paid. */
export async function setBudgetAuthorization(
  tx: PostgresRepository,
  input: BudgetAuthorizationInput,
): Promise<Record<string, unknown>> {
  const current = await tx.query<{ committed_units: string; spent_units: string }>(
    `SELECT committed_units, spent_units
       FROM institution_budget_lines
      WHERE institution_id = $1
        AND fiscal_period_id = $2
        AND category_id = (SELECT id FROM budget_categories WHERE institution_kind = $3 AND category_code = $4)
      FOR UPDATE`,
    [input.institutionId, input.fiscalPeriodId, input.institutionKind, input.categoryCode],
  );
  if (input.authorizedUnits < 0n) throw new Error('Budget authorization cannot be negative');
  const reserved = BigInt(current.rows[0]?.committed_units ?? '0') + BigInt(current.rows[0]?.spent_units ?? '0');
  if (input.authorizedUnits < reserved) throw new Error('Budget authorization cannot be below committed or spent funds');
  await tx.query(
    `INSERT INTO institution_budget_lines
      (institution_id, fiscal_period_id, category_id, authorized_units, status, rule_version, created_game_day)
     VALUES ($1, $2, (SELECT id FROM budget_categories WHERE institution_kind = $3 AND category_code = $4), $5, 'ACTIVE', $6, $7)
     ON CONFLICT (institution_id, fiscal_period_id, category_id)
     DO UPDATE SET authorized_units = EXCLUDED.authorized_units, rule_version = EXCLUDED.rule_version, updated_at = CURRENT_TIMESTAMP`,
    [input.institutionId, input.fiscalPeriodId, input.institutionKind, input.categoryCode, input.authorizedUnits, input.ruleVersion, input.createdGameDay],
  );
  const result = await tx.query(
    `SELECT b.*, c.category_code
       FROM institution_budget_lines b
       JOIN budget_categories c ON c.id = b.category_id
      WHERE b.institution_id = $1 AND b.fiscal_period_id = $2 AND b.category_id =
        (SELECT id FROM budget_categories WHERE institution_kind = $3 AND category_code = $4)`,
    [input.institutionId, input.fiscalPeriodId, input.institutionKind, input.categoryCode],
  );
  await tx.query(`SELECT earth_record_institution_financial_event($1,$2,$3,$4,NULL,NULL,$5,NULL,NULL,$6)`, [input.institutionId, input.createdGameDay, current.rows[0] ? 'BUDGET_AMENDED' : 'BUDGET_AUTHORIZED', input.authorizedUnits, input.categoryCode, `budget:${input.institutionId}:${input.fiscalPeriodId}:${input.categoryCode}`]);
  return result.rows[0] ?? {};
}
