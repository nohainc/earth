import type { PostgresRepository } from './repository.ts';

// @mutation-boundary deterministic-settlement: one bounded snapshot per active institution and finalized day.
// @mutation-boundary caller-owned-transaction: invoked only from the daily settlement transaction.
export async function refreshInstitutionFinancialSnapshots(
  repository: PostgresRepository,
  gameDay: number,
): Promise<{ gameDay: number; institutionsRefreshed: number }> {
  const result = await repository.query<{ count: number }>(
    `WITH institution_flows AS (
       SELECT o.id AS institution_id,
              COALESCE(SUM(CASE WHEN e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0)::BIGINT AS revenue_units,
              COALESCE(SUM(CASE WHEN e.delta_units < 0 THEN -e.delta_units ELSE 0 END), 0)::BIGINT AS spending_units
         FROM institutions i
         JOIN owner_registry o ON o.id = i.id AND o.owner_type IN ('EARTH', 'CORPORATION')
         JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1
         JOIN economic_entries e ON e.account_id = a.id
         JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = $1
        WHERE i.status = 'ACTIVE'
        GROUP BY o.id
     ),
     institution_balances AS (
       SELECT o.id AS institution_id,
              COALESCE(SUM(a.balance_units) FILTER (WHERE a.account_type = 'TREASURY'), 0)::BIGINT AS treasury_units,
              COALESCE(SUM(a.balance_units) FILTER (WHERE a.account_type = 'OPERATIONS'), 0)::BIGINT AS operations_units,
              COALESCE(SUM(a.balance_units) FILTER (WHERE a.account_type = 'RESERVE'), 0)::BIGINT AS reserve_units
         FROM institutions i
         JOIN owner_registry o ON o.id = i.id AND o.owner_type IN ('EARTH', 'CORPORATION')
         LEFT JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.status = 'ACTIVE'
        WHERE i.status = 'ACTIVE'
        GROUP BY o.id
     ),
     budgets AS (
       SELECT institution_id,
              COALESCE(SUM(authorized_units), 0)::BIGINT AS authorized_units,
              COALESCE(SUM(committed_units), 0)::BIGINT AS committed_units,
              COALESCE(SUM(spent_units), 0)::BIGINT AS spent_units
         FROM institution_budget_lines
        WHERE status = 'ACTIVE'
        GROUP BY institution_id
     ),
     receivables AS (
       SELECT creditor_economic_id,
              COALESCE(SUM(CASE WHEN status IN ('DUE', 'PARTIAL') THEN principal_due_units + interest_due_units - paid_units ELSE 0 END), 0)::BIGINT AS receivable_units,
              COALESCE(SUM(CASE WHEN status = 'ARREARS' THEN principal_due_units + interest_due_units - paid_units ELSE 0 END), 0)::BIGINT AS arrears_units
         FROM financial_obligations
        GROUP BY creditor_economic_id
     )
     INSERT INTO institution_financial_snapshots (
       institution_id, game_day, cash_treasury_units, cash_operations_units, cash_reserve_units,
       period_revenue_units, period_spending_units, budget_authorized_units, budget_committed_units,
       budget_spent_units, tax_receivable_units, arrears_units, financial_state, rules_version
     )
     SELECT i.id, $1,
            COALESCE(ab.treasury_units, 0), COALESCE(ab.operations_units, 0), COALESCE(ab.reserve_units, 0),
            COALESCE(f.revenue_units, 0), COALESCE(f.spending_units, 0),
            COALESCE(b.authorized_units, 0), COALESCE(b.committed_units, 0), COALESCE(b.spent_units, 0),
            COALESCE(r.receivable_units, 0), COALESCE(r.arrears_units, 0), ofs.status, 'institution-finance-v1'
       FROM institutions i
       JOIN owner_registry o ON o.id = i.id AND o.owner_type IN ('EARTH', 'CORPORATION')
       LEFT JOIN institution_flows f ON f.institution_id = i.id
       LEFT JOIN institution_balances ab ON ab.institution_id = i.id
       LEFT JOIN budgets b ON b.institution_id = i.id
       LEFT JOIN receivables r ON r.creditor_economic_id = o.economic_id
       LEFT JOIN organization_financial_states ofs ON ofs.organization_id = i.id
      WHERE i.status = 'ACTIVE'
     ON CONFLICT (institution_id, game_day) DO UPDATE SET
       cash_treasury_units = EXCLUDED.cash_treasury_units,
       cash_operations_units = EXCLUDED.cash_operations_units,
       cash_reserve_units = EXCLUDED.cash_reserve_units,
       period_revenue_units = EXCLUDED.period_revenue_units,
       period_spending_units = EXCLUDED.period_spending_units,
       budget_authorized_units = EXCLUDED.budget_authorized_units,
       budget_committed_units = EXCLUDED.budget_committed_units,
       budget_spent_units = EXCLUDED.budget_spent_units,
       tax_receivable_units = EXCLUDED.tax_receivable_units,
       arrears_units = EXCLUDED.arrears_units,
       financial_state = EXCLUDED.financial_state,
       rules_version = EXCLUDED.rules_version,
       updated_at = CURRENT_TIMESTAMP
     RETURNING institution_id`,
    [gameDay],
  );
  return { gameDay, institutionsRefreshed: result.rows.length };
}
