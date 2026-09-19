import type { PostgresRepository } from './repository.ts';
import { getHouseFinancialProjection, getHouseNextSettlementProjection } from './financial-projections.ts';
import { getTaxStatement } from './tax-statement-postgres.ts';
import { getV5HouseCapacity } from './v5-capacity-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

type ObligationStatus = 'CURRENT' | 'DUE' | 'ARREARS' | 'DELINQUENT';

type ObligationClaim = {
  id: string;
  sourceType: string;
  gameDay: number | null;
  dueGameDay: number | null;
  amountUnits: string;
  paidUnits: string;
  remainingUnits: string;
  status: ObligationStatus;
};

type ObligationSection = {
  claims: ObligationClaim[];
  status: ObligationStatus;
  totalDueUnits: string;
  totalPaidUnits: string;
  totalRemainingUnits: string;
};

function normalizeObligationStatus(value: unknown, fallback: ObligationStatus = 'DUE'): ObligationStatus {
  const raw = String(value ?? '').toUpperCase();
  if (raw === 'PAID' || raw === 'SETTLED' || raw === 'CURRENT' || raw === 'CANCELLED') return 'CURRENT';
  if (raw === 'DELINQUENT' || raw === 'DEFAULT' || raw === 'SUSPENDED' || raw === 'EARTH_RECEIVERSHIP') return 'DELINQUENT';
  if (raw === 'ARREARS' || raw === 'RESTRICTED' || raw === 'PRODUCTIVE_CAPACITY_SUSPENDED' || raw === 'EARTH_RENT_ARREARS') return 'ARREARS';
  if (raw === 'DUE' || raw === 'PARTIAL' || raw === 'GRACE' || raw === 'EXPANSION_BLOCKED' || raw === 'EXPANSION_SPENDING_RESTRICTED') return 'DUE';
  return fallback;
}

function asUnits(value: unknown): bigint {
  try { return BigInt(String(value ?? '0')); } catch { return 0n; }
}

function claim(id: unknown, sourceType: string, row: Record<string, unknown>, amount: unknown, paid: unknown, rawStatus: unknown, statusOverride?: unknown): ObligationClaim {
  const amountUnits = asUnits(amount);
  const paidUnits = asUnits(paid);
  const remainingUnits = amountUnits - paidUnits < 0n ? 0n : amountUnits - paidUnits;
  return {
    id: String(id),
    sourceType,
    gameDay: row.game_day == null ? null : Number(row.game_day),
    dueGameDay: row.due_game_day == null ? null : Number(row.due_game_day),
    amountUnits: amountUnits.toString(),
    paidUnits: paidUnits.toString(),
    remainingUnits: remainingUnits.toString(),
    status: normalizeObligationStatus(statusOverride ?? rawStatus, remainingUnits === 0n ? 'CURRENT' : 'DUE'),
  };
}

function obligationSection(claims: ObligationClaim[]): ObligationSection {
  const totalDue = claims.reduce((sum, item) => sum + asUnits(item.amountUnits), 0n);
  const totalPaid = claims.reduce((sum, item) => sum + asUnits(item.paidUnits), 0n);
  const totalRemaining = claims.reduce((sum, item) => sum + asUnits(item.remainingUnits), 0n);
  const status = claims.some((item) => item.status === 'DELINQUENT') ? 'DELINQUENT'
    : claims.some((item) => item.status === 'ARREARS') ? 'ARREARS'
    : claims.some((item) => item.status === 'DUE') ? 'DUE' : 'CURRENT';
  return { claims, status, totalDueUnits: totalDue.toString(), totalPaidUnits: totalPaid.toString(), totalRemainingUnits: totalRemaining.toString() };
}

export type HouseFinanceOverview = {
  contractVersion: 'v5-house-finance-overview-1';
  houseId: string;
  clock: {
    gameDay: number;
    gameMinute: number;
    totalGameMinutes: number;
    serverNow: string;
  };
  wallet: { accountId: string | null; balanceUnits: string };
  liquidity: {
    walletUnits: string;
    availableToSpendUnits: string;
    nextSettlementGameDay: number;
  };
  obligations: {
    capacity: ObligationSection & { distress: { active: boolean; status: ObligationStatus; resolution: { getRoute: string; openRoute: string; method: 'POST'; actionLabel: string; available: boolean } } };
    taxes: ObligationSection;
    loans: ObligationSection;
    other: ObligationSection;
    dailyNeeds: Record<string, unknown> | null;
  };
  capacity: { summary: Record<string, unknown> | null };
  bank: {
    deposits: Array<Record<string, unknown>>;
    loans: Array<Record<string, unknown>>;
    summary: { depositPrincipalUnits: string; loanOutstandingUnits: string };
  };
  tax: {
    rules: Array<Record<string, unknown>>;
    obligations: Array<Record<string, unknown>>;
    constitutionSnapshotId: string | null;
    generatedFrom: string;
  };
  cashflow: {
    historical: Record<string, unknown>;
    nextSettlement: Record<string, unknown>;
    recentTransactions: Array<Record<string, unknown>>;
  };
};

export async function getHouseFinanceOverview(
  repository: PostgresRepository,
  houseId: string,
  humanId: string,
): Promise<HouseFinanceOverview> {
  const [clock, account, maintenance, taxObligations, deposits, loans, loanSchedules, otherObligations, transactions, capacity, capacityObligations, taxStatement, projection, nextSettlement] = await Promise.all([
    readAuthoritativeGameTime(repository),
    repository.query<{ account_id: string; balance_units: string }>(`SELECT a.id::TEXT AS account_id, a.balance_units::TEXT AS balance_units
      FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      WHERE o.id = $1 AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [houseId]),
    repository.query(`SELECT game_day, food_required_units, food_consumed_units, food_shortfall_units,
             status, shortfall_notes
      FROM personal_life_maintenance WHERE human_id = $1 ORDER BY game_day DESC LIMIT 1`, [humanId]),
    repository.query(`SELECT id, tax_type, tax_base_units::TEXT, amount_units::TEXT,
             rule_version, game_day, status
      FROM tax_obligations t JOIN owner_registry o ON o.economic_id = t.taxpayer_economic_id
      WHERE o.id = $1 ORDER BY t.game_day DESC, t.id DESC`, [houseId]),
    repository.query(`SELECT d.id, d.principal_units::TEXT, d.accrued_interest_units::TEXT,
             d.rate_bps, d.start_total_game_minute, d.maturity_total_game_minute, d.status,
             d.created_transaction_id, d.payout_transaction_id, d.correlation_id
      FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
      WHERE o.id = $1 ORDER BY d.id DESC`, [houseId]),
    repository.query(`SELECT l.id, l.original_principal_units::TEXT, l.outstanding_principal_units::TEXT,
             l.accrued_interest_units::TEXT, l.rate_bps, l.term_days, l.origination_game_day,
             l.maturity_game_day, l.next_payment_game_day, l.status
      FROM bank_loans l JOIN owner_registry o ON o.economic_id = l.borrower_economic_id
      WHERE o.id = $1 ORDER BY l.origination_game_day DESC, l.id`, [houseId]),
    repository.query(`SELECT s.id, s.loan_id, s.due_game_day,
             s.principal_due_units::TEXT, s.interest_due_units::TEXT,
             s.paid_units::TEXT, s.status, l.status AS loan_status
      FROM bank_loan_schedules s JOIN bank_loans l ON l.id = s.loan_id
      JOIN owner_registry o ON o.economic_id = l.borrower_economic_id
      WHERE o.id = $1 ORDER BY s.due_game_day, s.installment_no`, [houseId]).catch(() => ({ rows: [] })),
    repository.query(`SELECT f.id, f.obligation_type, f.source_id, f.due_game_day,
             f.principal_due_units::TEXT, f.interest_due_units::TEXT,
             f.paid_units::TEXT, f.status
      FROM financial_obligations f JOIN owner_registry o ON o.economic_id = f.debtor_economic_id
      WHERE o.id = $1 AND f.obligation_type NOT IN ('TAX','CAPACITY_RENT')
      ORDER BY f.due_game_day, f.id`, [houseId]).catch(() => ({ rows: [] })),
    repository.query(`SELECT t.id, t.game_day, t.game_minute, t.transaction_kind, t.correlation_id,
             e.asset_id, e.delta_units::TEXT, e.reason_code
      FROM economic_transactions t JOIN economic_entries e ON e.transaction_id = t.id
      WHERE e.account_id IN (SELECT a.id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1)
      ORDER BY t.id DESC LIMIT 100`, [houseId]),
    getV5HouseCapacity(repository, houseId).catch(() => null),
    repository.query(`SELECT o.id, o.game_day, o.usage_units::TEXT, o.assessed_units::TEXT,
             o.paid_units::TEXT, o.status, o.schedule_id, o.financial_obligation_id
      FROM v5_capacity_obligations o WHERE o.house_id = $1
      ORDER BY o.game_day DESC, o.created_at DESC LIMIT 100`, [houseId]).catch(() => ({ rows: [] })),
    getTaxStatement(repository, humanId),
    getHouseFinancialProjection(repository, houseId),
    getHouseNextSettlementProjection(repository, houseId),
  ]);

  const walletUnits = BigInt(account.rows[0]?.balance_units ?? '0');
  const availableToSpendUnits = walletUnits;
  const depositPrincipalUnits = deposits.rows.reduce((sum, row) => sum + BigInt(row.principal_units ?? 0), 0n);
  const loanOutstandingUnits = loans.rows.reduce((sum, row) => sum + BigInt(row.outstanding_principal_units ?? 0) + BigInt(row.accrued_interest_units ?? 0), 0n);
  const canonicalRules = Object.entries(taxStatement.constitutionalTaxRules ?? {}).map(([code, value]) => ({
    code,
    value,
    versionId: taxStatement.constitutionalTaxVersionIds?.[code] ?? null,
    provenance: taxStatement.constitutionalTaxProvenance?.[code] ?? null,
  }));

  const taxClaims = taxObligations.rows.map((row) => claim(row.id, 'TAX', row, row.amount_units, row.status === 'PAID' ? row.amount_units : '0', row.status));
  const capacityDelinquencyStatus = capacity?.delinquency?.status;
  const delinquencyOverride = ['ARREARS', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EARTH_RENT_ARREARS', 'EARTH_RECEIVERSHIP'].includes(String(capacityDelinquencyStatus ?? '').toUpperCase())
    ? capacityDelinquencyStatus
    : undefined;
  const capacityClaims = capacityObligations.rows.map((row) => claim(row.id, 'V5_CAPACITY', row, row.assessed_units, row.paid_units, row.status, delinquencyOverride));
  const loanClaims = loanSchedules.rows.map((row) => claim(row.id, 'LOAN_SCHEDULE', row, asUnits(row.principal_due_units) + asUnits(row.interest_due_units), row.paid_units, row.status, row.loan_status));
  const otherClaims = otherObligations.rows.map((row) => claim(row.id, String(row.obligation_type ?? 'OTHER'), row, asUnits(row.principal_due_units) + asUnits(row.interest_due_units), row.paid_units, row.status));
  const capacitySection = obligationSection(capacityClaims);
  const normalizedDelinquency = normalizeObligationStatus(capacityDelinquencyStatus, capacitySection.status);
  const capacityStatus = normalizedDelinquency === 'DELINQUENT' || normalizedDelinquency === 'ARREARS' ? normalizedDelinquency : capacitySection.status;
  const capacityDistress = capacityStatus === 'ARREARS' || capacityStatus === 'DELINQUENT' || capacityClaims.some((item) => item.status === 'ARREARS' || item.status === 'DELINQUENT');
  const canOpenCapacityResolution = ['PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_BLOCKED'].includes(String(capacityDelinquencyStatus ?? '').toUpperCase());

  return {
    contractVersion: 'v5-house-finance-overview-1',
    houseId,
    clock: {
      gameDay: clock.gameDay,
      gameMinute: clock.gameMinute,
      totalGameMinutes: clock.totalGameMinutes,
      serverNow: clock.serverNow,
    },
    wallet: { accountId: account.rows[0]?.account_id ?? null, balanceUnits: walletUnits.toString() },
    liquidity: {
      walletUnits: walletUnits.toString(),
      availableToSpendUnits: availableToSpendUnits.toString(),
      nextSettlementGameDay: clock.gameDay + 1,
    },
    obligations: {
      capacity: {
        ...capacitySection,
        status: capacityStatus,
        distress: {
          active: capacityDistress,
          status: capacityStatus,
          resolution: {
            getRoute: '/api/v5/house/capacity-resolution',
            openRoute: '/api/v5/house/capacity-resolution',
            method: 'POST',
            actionLabel: 'OPEN CAPACITY RESOLUTION',
            available: canOpenCapacityResolution,
          },
        },
      },
      taxes: obligationSection(taxClaims),
      loans: obligationSection(loanClaims),
      other: obligationSection(otherClaims),
      dailyNeeds: maintenance.rows[0] ?? null,
    },
    capacity: { summary: capacity },
    bank: {
      deposits: deposits.rows,
      loans: loans.rows,
      summary: { depositPrincipalUnits: depositPrincipalUnits.toString(), loanOutstandingUnits: loanOutstandingUnits.toString() },
    },
    tax: {
      rules: canonicalRules,
      obligations: taxObligations.rows,
      constitutionSnapshotId: taxStatement.constitutionSnapshotId,
      generatedFrom: 'postgres-constitutional-tax-v5',
    },
    cashflow: {
      historical: { ...projection, basis: 'ALL_TIME_LEDGER_AGGREGATE' },
      nextSettlement,
      recentTransactions: transactions.rows,
    },
  };
}
