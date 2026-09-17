import type { PostgresRepository } from './repository.ts';
import { getV5HouseCapacity } from './v5-capacity-postgres.ts';

type FlowRow = { transaction_kind: string; inflow_units: string; outflow_units: string };

async function ledgerFlows(repository: PostgresRepository, ownerEconomicId: string): Promise<FlowRow[]> {
  const result = await repository.query<FlowRow>(
    `SELECT t.transaction_kind,
            COALESCE(SUM(CASE WHEN e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0)::TEXT AS inflow_units,
            COALESCE(SUM(CASE WHEN e.delta_units < 0 THEN -e.delta_units ELSE 0 END), 0)::TEXT AS outflow_units
       FROM economic_transactions t
       JOIN economic_entries e ON e.transaction_id = t.id
       JOIN economic_accounts a ON a.id = e.account_id
      WHERE a.owner_economic_id = $1 AND e.asset_id = 1
      GROUP BY t.transaction_kind ORDER BY t.transaction_kind`, [ownerEconomicId],
  );
  return result.rows;
}

function total(rows: FlowRow[], field: 'inflow_units' | 'outflow_units'): string {
  return rows.reduce((sum, row) => sum + BigInt(row[field] ?? '0'), 0n).toString();
}

function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)])) as T;
  }
  return value;
}

export async function getHouseFinancialProjection(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ economic_id: string }>('SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = \'HOUSE\'', [houseId])).rows[0];
  if (!owner) throw new Error('House financial owner not found');
  const cash = await repository.query<{ balance_units: string }>(`SELECT COALESCE(SUM(balance_units), 0)::TEXT AS balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE'`, [owner.economic_id]);
  const flows = await ledgerFlows(repository, owner.economic_id);
  const taxes = await repository.query<{ paid_units: string }>(`SELECT COALESCE(SUM(paid_units), 0)::TEXT AS paid_units FROM financial_obligations WHERE debtor_economic_id = $1 AND obligation_type = 'TAX'`, [owner.economic_id]);
  const loans = await repository.query<{ outstanding_principal_units: string; accrued_interest_units: string }>('SELECT outstanding_principal_units::TEXT, accrued_interest_units::TEXT FROM bank_loans WHERE borrower_economic_id = $1 AND status NOT IN (\'PAID\', \'CANCELLED\')', [owner.economic_id]);
  const capacity = await getV5HouseCapacity(repository, houseId).catch(() => null);
  const income = total(flows, 'inflow_units');
  const expenses = total(flows, 'outflow_units');
  return toJsonSafe({
    scope: 'HOUSE', principalId: houseId, cashBalanceUnits: cash.rows[0]?.balance_units ?? '0', incomeUnits: income,
    expenseUnits: expenses, taxUnits: taxes.rows[0]?.paid_units ?? '0',
    loanUnits: loans.rows.reduce((sum, row) => sum + BigInt(row.outstanding_principal_units) + BigInt(row.accrued_interest_units), 0n).toString(),
    netCashFlowUnits: (BigInt(income) - BigInt(expenses)).toString(), byTransactionKind: flows,
    capacity,
    capacitySource: capacity ? 'postgres-v5-structural-settlement-profile' : 'unavailable-canonical-capacity-read-model',
  });
}

export async function getInstitutionFinancialProjection(repository: PostgresRepository, institutionId: string): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ economic_id: string; owner_type: string }>('SELECT economic_id, owner_type FROM owner_registry WHERE id = $1 AND owner_type IN (\'EARTH\', \'CORPORATION\')', [institutionId])).rows[0];
  if (!owner) throw new Error('Institution financial owner not found');
  const [accounts, lines, flows] = await Promise.all([
    repository.query<{ account_type: string; balance_units: string }>(`SELECT account_type, COALESCE(SUM(balance_units), 0)::TEXT AS balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE') AND status = 'ACTIVE' GROUP BY account_type`, [owner.economic_id]),
    repository.query<{ authorized: string; committed: string; spent: string }>(`SELECT COALESCE(SUM(authorized_units), 0)::TEXT AS authorized, COALESCE(SUM(committed_units), 0)::TEXT AS committed, COALESCE(SUM(spent_units), 0)::TEXT AS spent FROM institution_budget_lines WHERE institution_id = $1`, [institutionId]),
    ledgerFlows(repository, owner.economic_id),
  ]);
  const cash = Object.fromEntries(accounts.rows.map((row) => [row.account_type.toLowerCase(), row.balance_units]));
  const budget = lines.rows[0] ?? { authorized: '0', committed: '0', spent: '0' };
  return {
    scope: owner.owner_type, principalId: institutionId, treasuryUnits: cash.treasury ?? '0', operationsUnits: cash.operations ?? '0', reserveUnits: cash.reserve ?? '0',
    authorizedUnits: budget.authorized, committedUnits: budget.committed, spentUnits: budget.spent,
    availableUnits: (BigInt(budget.authorized) - BigInt(budget.committed) - BigInt(budget.spent)).toString(),
    revenueUnits: total(flows.rows, 'inflow_units'), expenseUnits: total(flows.rows, 'outflow_units'), byTransactionKind: flows.rows,
  };
}
