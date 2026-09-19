import type { PostgresRepository } from './repository.ts';
import { getV5HouseCapacity } from './v5-capacity-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

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

type SettlementItem = {
  category: string;
  direction: 'INFLOW' | 'OUTFLOW';
  amountUnits: string;
  sourceType: string;
  sourceId: string | null;
  status: string;
};

/**
 * Forecasts the next closed-day settlement from facts that are already known.
 * This is deliberately separate from ledgerFlows(): it must never present
 * historical totals as if they were a one-day forecast.
 */
export async function getHouseNextSettlementProjection(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ economic_id: string }>(
    "SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'HOUSE'", [houseId],
  )).rows[0];
  if (!owner) throw new Error('House financial owner not found');
  const clock = await readAuthoritativeGameTime(repository);
  const settlementGameDay = clock.gameDay + 1;

  const [taxes, otherObligations, capacity, buildings, loanSchedules, licenses, deposits] = await Promise.all([
    repository.query<{ id: string; amount_units: string; paid_units: string }>(
      `SELECT id, principal_due_units::TEXT AS amount_units, paid_units::TEXT
         FROM financial_obligations
        WHERE debtor_economic_id = $1 AND obligation_type = 'TAX'
          AND due_game_day = $2 AND status IN ('DUE','PARTIAL','ARREARS')`, [owner.economic_id, settlementGameDay],
    ),
    repository.query<{ id: string; obligation_type: string; principal_due_units: string; interest_due_units: string; paid_units: string }>(
      `SELECT id, obligation_type, principal_due_units::TEXT, interest_due_units::TEXT, paid_units::TEXT
         FROM financial_obligations
        WHERE debtor_economic_id = $1 AND obligation_type NOT IN ('TAX')
          AND due_game_day = $2 AND status IN ('DUE','PARTIAL','ARREARS')`, [owner.economic_id, settlementGameDay],
    ),
    repository.query<{ id: string; assessed_units: string; paid_units: string }>(
      `SELECT id, assessed_units::TEXT, paid_units::TEXT
         FROM v5_capacity_obligations
        WHERE house_id = $1 AND game_day = $2 AND status IN ('DUE','PARTIAL','ARREARS')`, [houseId, settlementGameDay],
    ),
    repository.query<{ id: string; operating_credit_units: string }>(
      `SELECT b.id, c.operating_credit_units::TEXT
         FROM buildings b
         JOIN building_catalog c ON c.id = b.catalog_id
         JOIN owner_registry o ON o.economic_id = b.owner_economic_id
        WHERE o.id = $1 AND b.status IN ('ACTIVE','COMPLETED')`, [houseId],
    ),
    repository.query<{ id: string; principal_due_units: string; interest_due_units: string; paid_units: string }>(
      `SELECT s.id, s.principal_due_units::TEXT, s.interest_due_units::TEXT, s.paid_units::TEXT
         FROM bank_loan_schedules s
         JOIN bank_loans l ON l.id = s.loan_id
        WHERE l.borrower_economic_id = $1 AND s.due_game_day = $2
          AND s.status IN ('DUE','PARTIAL','ARREARS')`, [owner.economic_id, settlementGameDay],
    ),
    repository.query<{ id: string; daily_fee_units: string }>(
      `SELECT id, daily_fee_units::TEXT
         FROM technology_license_contracts
        WHERE licensee_economic_id = $1 AND status = 'ACTIVE'
          AND effective_from_game_day <= $2
          AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)
          AND paid_through_game_day < $2`, [owner.economic_id, settlementGameDay],
    ),
    repository.query<{ id: string; principal_units: string; rate_bps: string }>(
      `SELECT id, principal_units::TEXT, rate_bps::TEXT
         FROM bank_deposits
        WHERE depositor_economic_id = $1 AND status IN ('ACTIVE','MATURED')`, [owner.economic_id],
    ),
  ]);

  const items: SettlementItem[] = [];
  const addOutflow = (category: string, amount: bigint, sourceType: string, sourceId: string | null, status = 'KNOWN') => {
    if (amount > 0n) items.push({ category, direction: 'OUTFLOW', amountUnits: amount.toString(), sourceType, sourceId, status });
  };
  const addInflow = (category: string, amount: bigint, sourceType: string, sourceId: string | null, status = 'ESTIMATED') => {
    if (amount > 0n) items.push({ category, direction: 'INFLOW', amountUnits: amount.toString(), sourceType, sourceId, status });
  };

  for (const row of taxes.rows) addOutflow('TAX', BigInt(row.amount_units ?? 0) - BigInt(row.paid_units ?? 0), 'TAX_OBLIGATION', row.id);
  for (const row of otherObligations.rows) addOutflow(String(row.obligation_type), BigInt(row.principal_due_units ?? 0) + BigInt(row.interest_due_units ?? 0) - BigInt(row.paid_units ?? 0), 'FINANCIAL_OBLIGATION', row.id);
  for (const row of capacity.rows) addOutflow('CAPACITY_RENT', BigInt(row.assessed_units ?? 0) - BigInt(row.paid_units ?? 0), 'CAPACITY_OBLIGATION', row.id);
  for (const row of buildings.rows) addOutflow('BUILDING_OPERATING_EXPENSE', BigInt(row.operating_credit_units ?? 0), 'BUILDING', row.id, 'BASE_ESTIMATE');
  for (const row of loanSchedules.rows) addOutflow('DEBT_SERVICE', BigInt(row.principal_due_units ?? 0) + BigInt(row.interest_due_units ?? 0) - BigInt(row.paid_units ?? 0), 'BANK_LOAN_SCHEDULE', row.id);
  for (const row of licenses.rows) addOutflow('LICENSE', BigInt(row.daily_fee_units ?? 0), 'TECHNOLOGY_LICENSE', row.id);
  for (const row of deposits.rows) addInflow('BANK_INTEREST', (BigInt(row.principal_units ?? 0) * BigInt(row.rate_bps ?? 0)) / 36500n, 'BANK_DEPOSIT', row.id);

  const inflows = items.filter((item) => item.direction === 'INFLOW').reduce((sum, item) => sum + BigInt(item.amountUnits), 0n);
  const outflows = items.filter((item) => item.direction === 'OUTFLOW').reduce((sum, item) => sum + BigInt(item.amountUnits), 0n);
  return toJsonSafe({
    gameDay: settlementGameDay,
    basis: 'KNOWN_OBLIGATIONS_AND_PREDICTABLE_FLOWS',
    inflowsUnits: inflows.toString(),
    outflowsUnits: outflows.toString(),
    netCashflowUnits: (inflows - outflows).toString(),
    items,
    generatedFrom: 'postgres-next-settlement-facts-v5',
  });
}

export async function getInstitutionFinancialProjection(repository: PostgresRepository, institutionId: string): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ economic_id: string; owner_type: string }>('SELECT economic_id, owner_type FROM owner_registry WHERE id = $1 AND owner_type IN (\'EARTH\', \'CORPORATION\')', [institutionId])).rows[0];
  if (!owner) throw new Error('Institution financial owner not found');
  const [accounts, resourceAccounts, lines, flows] = await Promise.all([
    repository.query<{ account_type: string; balance_units: string }>(`SELECT account_type, COALESCE(SUM(balance_units), 0)::TEXT AS balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE') AND status = 'ACTIVE' GROUP BY account_type`, [owner.economic_id]),
    repository.query<{ code: string; balance_units: string }>(`SELECT lower(ea.code) AS code, COALESCE(SUM(a.balance_units), 0)::TEXT AS balance_units FROM economic_accounts a JOIN economic_assets ea ON ea.id = a.asset_id WHERE a.owner_economic_id = $1 AND a.account_type = 'INVENTORY' AND ea.asset_kind = 'RESOURCE' AND a.status = 'ACTIVE' GROUP BY ea.code`, [owner.economic_id]),
    repository.query<{ authorized: string; committed: string; spent: string }>(`SELECT COALESCE(SUM(authorized_units), 0)::TEXT AS authorized, COALESCE(SUM(committed_units), 0)::TEXT AS committed, COALESCE(SUM(spent_units), 0)::TEXT AS spent FROM institution_budget_lines WHERE institution_id = $1`, [institutionId]),
    ledgerFlows(repository, owner.economic_id),
  ]);
  const cash = Object.fromEntries(accounts.rows.map((row) => [row.account_type.toLowerCase(), row.balance_units]));
  const resourceBalances: Record<string, string> = {
    energy: '0', food: '0', material: '0', components: '0', compute: '0',
    ...Object.fromEntries(resourceAccounts.rows.map((row) => [row.code, row.balance_units])),
  };
  const budget = lines.rows[0] ?? { authorized: '0', committed: '0', spent: '0' };
  return {
    scope: owner.owner_type, principalId: institutionId, treasuryUnits: cash.treasury ?? '0', operationsUnits: cash.operations ?? '0', reserveUnits: cash.reserve ?? '0',
    resourceBalances,
    authorizedUnits: budget.authorized, committedUnits: budget.committed, spentUnits: budget.spent,
    availableUnits: (BigInt(budget.authorized) - BigInt(budget.committed) - BigInt(budget.spent)).toString(),
    revenueUnits: total(flows, 'inflow_units'), expenseUnits: total(flows, 'outflow_units'), byTransactionKind: flows,
  };
}
