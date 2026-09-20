import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { formatCreditUnits } from './money.ts';

// @mutation-boundary deterministic-settlement: one projection row is recomputed for a finalized day.
// @mutation-boundary caller-owned-transaction: projection refresh is a scheduler phase transaction.
export async function refreshHouseDailyStatementsInTransaction(repository: PostgresRepository, gameDay: number): Promise<number> {
  const result = await repository.query<{ count: number }>(
    'SELECT earth_refresh_house_daily_statements($1) AS count',
    [gameDay],
  );
  return Number(result.rows[0]?.count ?? 0);
}

type SummaryEvent = {
  id: string;
  type: string;
  title: string;
  details: string;
  gameDay: number;
  gameMinute: number | null;
  source: 'GAME_EVENT' | 'NOTIFICATION';
  category: string;
};

function units(value: unknown): bigint {
  try {
    return BigInt(String(value ?? '0'));
  } catch {
    return 0n;
  }
}

function unitString(value: unknown): string {
  return units(value).toString();
}

function eventRows(rows: Record<string, unknown>[], source: 'GAME_EVENT' | 'NOTIFICATION'): SummaryEvent[] {
  return rows.map((row) => ({
    id: String(row.id),
    type: String(row.event_type ?? row.notification_type ?? 'EVENT'),
    title: String(row.title),
    details: row.details == null ? (row.body == null ? '' : String(row.body)) : String(row.details),
    gameDay: Number(row.game_day),
    gameMinute: row.game_minute == null ? null : Number(row.game_minute),
    source,
    category: String(row.category ?? source),
  }));
}

function chronologicalEvents(rows: SummaryEvent[]): SummaryEvent[] {
  return [...rows].sort((a, b) =>
    (a.gameMinute ?? Number.MAX_SAFE_INTEGER) - (b.gameMinute ?? Number.MAX_SAFE_INTEGER)
    || a.source.localeCompare(b.source)
    || a.id.localeCompare(b.id));
}

function jsonObject(value: unknown): Record<string, string> {
  const parsed = typeof value === 'string' ? JSON.parse(value || '{}') : value;
  return Object.fromEntries(Object.entries((parsed ?? {}) as Record<string, unknown>).map(([key, item]) => [key, String(item)]));
}

function positiveUnitKeys(value: unknown): string[] {
  return Object.entries(jsonObject(value))
    .filter(([, amount]) => units(amount) > 0n)
    .map(([key]) => key);
}

function cashflowCategory(row: Record<string, unknown>): string {
  const source = String(row.source_type ?? '').toUpperCase();
  const kind = String(row.transaction_kind ?? '').toUpperCase();
  if (source.includes('TAX') || kind.includes('TAX')) return 'TAX';
  if (source.includes('CAPACITY') || kind.includes('CAPACITY')) return 'CAPACITY';
  if (source.includes('MARKET') || kind.includes('MARKET')) return 'MARKET';
  if (source.includes('RESEARCH') || kind.includes('RESEARCH')) return 'RESEARCH';
  if (source.includes('BUILDING_CONSTRUCTION') || source.includes('CONSTRUCTION') || kind.includes('CONSTRUCTION') || kind.includes('PUBLIC_CONSTRUCTION')) return 'CONSTRUCTION';
  if (source.includes('BUILDING') || source.includes('OPERATING') || kind.includes('TIER') || kind.includes('RETROFIT') || kind.includes('OVERHAUL')) return 'BUILDING_OPERATIONS';
  return 'OTHER';
}

export async function getHouseDailySummary(
  repository: PostgresRepository,
  houseId: string,
  requestedDay?: number,
) {
  const clock = await readAuthoritativeGameTime(repository);
  const currentGameDay = clock.gameDay;
  const summaryDay = requestedDay ?? Math.max(0, currentGameDay - 1);
  if (!Number.isInteger(summaryDay) || summaryDay < 0 || summaryDay >= currentGameDay) {
    throw new Error('Summary day must be a completed game day');
  }

  const [statement, cashflow, market, events, notifications, operatedBuildings, v5Capacity, needs, buildingSettlements] = await Promise.all([
    repository.query(`
      SELECT s.opening_assets, s.closing_assets, s.production, s.consumption, s.market_activity,
             s.obligations, s.exceptions, s.net_credit_units,
             s.created_at AS statement_created_at, s.updated_at AS statement_updated_at,
             r.status AS settlement_status, r.rules_version, r.completed_at AS finalized_at
      FROM house_daily_statements s
      LEFT JOIN daily_settlement_runs r ON r.game_day = s.game_day
      WHERE s.house_id = $1 AND s.game_day = $2`, [houseId, summaryDay]),
    repository.query(`
      SELECT t.transaction_kind, t.source_type,
             COALESCE(SUM(CASE WHEN e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0)::text AS inflow_units,
             COALESCE(SUM(CASE WHEN e.delta_units < 0 THEN -e.delta_units ELSE 0 END), 0)::text AS outflow_units
      FROM economic_transactions t
      JOIN economic_entries e ON e.transaction_id = t.id
      JOIN economic_accounts a ON a.id = e.account_id
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      JOIN economic_assets asset ON asset.id = e.asset_id
      WHERE o.id = $1 AND t.game_day = $2 AND asset.code = 'CREDIT'
      GROUP BY t.transaction_kind, t.source_type`, [houseId, summaryDay]),
    repository.query(`
      SELECT i.symbol AS commodity,
             COALESCE(SUM(CASE WHEN f.buyer_economic_id = owner.economic_id THEN f.quantity_units ELSE 0 END), 0)::text AS bought_units,
             COALESCE(SUM(CASE WHEN f.seller_economic_id = owner.economic_id THEN f.quantity_units ELSE 0 END), 0)::text AS sold_units,
             COALESCE(SUM(CASE WHEN f.buyer_economic_id = owner.economic_id THEN f.gross_quote_units ELSE 0 END), 0)::text AS credit_spent_units,
             COALESCE(SUM(CASE WHEN f.seller_economic_id = owner.economic_id THEN f.gross_quote_units ELSE 0 END), 0)::text AS credit_received_units,
             COALESCE(SUM(f.quantity_units), 0)::text AS volume_units
      FROM market_fills f
      JOIN market_batches b ON b.id = f.batch_id
      JOIN market_instruments i ON i.id = f.instrument_id
      JOIN owner_registry owner ON owner.id = $1
      WHERE b.game_day = $2
        AND (f.buyer_economic_id = owner.economic_id OR f.seller_economic_id = owner.economic_id)
      GROUP BY i.symbol ORDER BY i.symbol`, [houseId, summaryDay]),
    repository.query(`
      SELECT id, event_type, title, details, game_day, game_minute, category
      FROM game_events
      WHERE actor_house_id = $1 AND game_day = $2
      ORDER BY created_at, id`, [houseId, summaryDay]),
    repository.query(`
      SELECT id, notification_type, notification_type AS event_type, title, body, body AS details,
             game_day, game_minute, 'NOTIFICATION' AS category, read_at
      FROM notifications
      WHERE house_id = $1 AND game_day = $2
      ORDER BY created_at, id`, [houseId, summaryDay]),
    repository.query(`
      SELECT COUNT(DISTINCT j.building_id)::text AS count
      FROM building_settlement_journals j
      JOIN owner_registry o ON o.economic_id = j.house_economic_id
      WHERE o.id = $1
        AND j.game_day = $2
        AND j.status IN ('OPERATED', 'PARTIAL')`, [houseId, summaryDay]),
    repository.query(`
      SELECT
        COALESCE(SUM(assessed_rent_units), 0)::text AS assessed,
        COALESCE(SUM(paid_rent_units), 0)::text AS paid,
        COALESCE(SUM(arrears_units), 0)::text AS arrears,
        COALESCE(MAX(delinquency_status), 'CURRENT') AS status
      FROM house_capacity_statements_v5
      WHERE house_id = $1 AND game_day = $2`, [houseId, summaryDay]),
    repository.query(`
      SELECT need_code, shortfall_units::text, risk_level
      FROM house_need_assessments
      WHERE house_id = $1 AND game_day = $2 AND shortfall_units > 0`, [houseId, summaryDay]),
    repository.query(`
      SELECT j.building_id, j.status, j.shortage_units
      FROM building_settlement_journals j
      JOIN owner_registry o ON o.economic_id = j.house_economic_id
      WHERE o.id = $1 AND j.game_day = $2`, [houseId, summaryDay]),
  ]);

  let authoritative = statement.rows[0] as Record<string, unknown> | undefined;
  if (!authoritative) {
    authoritative = {
      opening_assets: {},
      closing_assets: {},
      production: {},
      consumption: {},
      market_activity: {},
      obligations: {},
      exceptions: {},
      net_credit_units: '0',
    };
  }

  const breakdownMap = new Map<string, { inflowUnits: bigint; outflowUnits: bigint }>();
  for (const row of cashflow.rows as Array<Record<string, unknown>>) {
    const category = cashflowCategory(row);
    const current = breakdownMap.get(category) ?? { inflowUnits: 0n, outflowUnits: 0n };
    current.inflowUnits += units(row.inflow_units);
    current.outflowUnits += units(row.outflow_units);
    breakdownMap.set(category, current);
  }
  const cashflowBreakdown = [...breakdownMap.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([category, values]) => ({
    category,
    inflowUnits: values.inflowUnits.toString(),
    outflowUnits: values.outflowUnits.toString(),
  }));
  const income = cashflowBreakdown.reduce((sum, row) => sum + units(row.inflowUnits), 0n);
  const expenses = cashflowBreakdown.reduce((sum, row) => sum + units(row.outflowUnits), 0n);
  const capacityRow = v5Capacity.rows[0] as Record<string, unknown> | undefined;
  const capacityRent = {
    assessed: unitString(capacityRow?.assessed),
    paid: unitString(capacityRow?.paid),
    arrears: unitString(capacityRow?.arrears),
    status: String(capacityRow?.status ?? 'CURRENT'),
  };
  const eventList = chronologicalEvents([
    ...eventRows(events.rows as Record<string, unknown>[], 'GAME_EVENT'),
    ...eventRows(notifications.rows as Record<string, unknown>[], 'NOTIFICATION'),
  ]);
  const buildings = eventList.filter((event) => event.type.startsWith('BUILDING_'));
  const research = eventList.filter((event) => event.type.startsWith('RESEARCH_') || event.type.startsWith('TECHNOLOGY_'));
  const governance = eventList.filter((event) => event.type.startsWith('PROPOSAL_') || event.type.startsWith('GOVERNANCE_'));
  const houseEvents = eventList.filter((event) => event.type.startsWith('HOUSE_') || event.type.startsWith('HUMAN_') || event.type.startsWith('AFFILIATION_'));
  const alerts = (notifications.rows as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    type: String(row.notification_type),
    title: String(row.title),
    body: String(row.body),
    read: row.read_at != null,
  }));

  const production = jsonObject(authoritative.production);
  const consumption = jsonObject(authoritative.consumption);
  const resourceCodes = new Set([...Object.keys(production), ...Object.keys(consumption)]);
  const resourceDeltas = [...resourceCodes].sort().map((resource) => ({
    resource,
    producedUnits: unitString(production[resource]),
    consumedUnits: unitString(consumption[resource]),
    netUnits: (units(production[resource]) - units(consumption[resource])).toString(),
  }));
  const closingAssets = jsonObject(authoritative.closing_assets);
  const actionableResources = new Set<string>();
  const resourceAttentionReasons = new Map<string, string>();
  const settlementAttentionReasons = new Map<string, string>();
  const addResourceAttention = (resource: string, reason: string) => {
    const code = resource.toUpperCase();
    actionableResources.add(code);
    if (!resourceAttentionReasons.has(code)) resourceAttentionReasons.set(code, reason);
  };
  for (const need of needs.rows as Array<Record<string, unknown>>) {
    const code = String(need.need_code ?? 'RESOURCE').toUpperCase();
    addResourceAttention(code, `House need ${code} had a ${need.shortfall_units} unit shortfall on game day ${summaryDay}.`);
  }
  for (const settlement of buildingSettlements.rows as Array<Record<string, unknown>>) {
    const status = String(settlement.status ?? '').toUpperCase();
    for (const resource of positiveUnitKeys(settlement.shortage_units)) {
      addResourceAttention(resource, `Building ${settlement.building_id} reported a ${resource} input shortage on game day ${summaryDay}.`);
    }
    if (status === 'STARVED' || status === 'PARTIAL') {
      settlementAttentionReasons.set(String(settlement.building_id), `Building ${settlement.building_id} reported ${status.toLowerCase()} operation during the game day ${summaryDay} settlement.`);
    }
  }
  for (const resource of Object.keys(consumption)) {
    if (resource === 'CREDIT') continue;
    if (closingAssets[resource] !== undefined && units(closingAssets[resource]) <= 0n && units(consumption[resource]) > 0n) {
      addResourceAttention(resource, `${resource} inventory was depleted after consumption on game day ${summaryDay}.`);
    }
  }
  const resourceShortfallCount = actionableResources.size;
  const statementView = {
    openingAssets: jsonObject(authoritative.opening_assets),
    closingAssets,
    production: jsonObject(authoritative.production),
    consumption: jsonObject(authoritative.consumption),
    marketActivity: authoritative.market_activity ?? {},
    obligations: authoritative.obligations ?? {},
    exceptions: authoritative.exceptions ?? {},
    netCreditUnits: String(authoritative.net_credit_units ?? '0'),
  };
  const settlementStatus = String(authoritative.settlement_status ?? 'UNKNOWN').toLowerCase();
  const statementMetadata = {
    gameDay: summaryDay,
    immutable: settlementStatus === 'completed' && authoritative.finalized_at != null,
    settlementStatus,
    rulesVersion: authoritative.rules_version == null ? null : String(authoritative.rules_version),
    finalizedAt: authoritative.finalized_at == null ? null : new Date(String(authoritative.finalized_at)).toISOString(),
    statementCreatedAt: authoritative.statement_created_at == null ? null : new Date(String(authoritative.statement_created_at)).toISOString(),
    statementUpdatedAt: authoritative.statement_updated_at == null ? null : new Date(String(authoritative.statement_updated_at)).toISOString(),
  };

  const highlights: Array<Record<string, unknown>> = [];
  if (expenses > income) highlights.push({
    id: 'negative_cashflow', severity: 'warning', title: 'Expenses exceeded income',
    reason: `Your House spent ${formatCreditUnits(expenses)} CREDIT and received ${formatCreditUnits(income)} CREDIT on game day ${summaryDay}.`,
    actionLabel: 'REVIEW FINANCE', targetSection: 'finance',
  });
  for (const event of buildings.filter((item) => item.type.includes('INACTIVE'))) highlights.push({
    id: `building-inactive:${event.id}`, severity: 'high', title: event.title,
    reason: event.details, actionLabel: 'VIEW BUILDINGS', targetSection: 'buildings',
  });
  for (const resource of actionableResources) highlights.push({
    id: `resource-attention:${resource}`, severity: 'warning', title: `${resource} requires attention`,
    reason: resourceAttentionReasons.get(resource) ?? `Resource conditions require review for game day ${summaryDay}.`,
    actionLabel: 'REVIEW RESOURCES', targetSection: 'buildings',
  });
  for (const [buildingId, reason] of settlementAttentionReasons) highlights.push({
    id: `building-settlement:${buildingId}`, severity: 'high', title: `Building ${buildingId} was starved`,
    reason, actionLabel: 'VIEW BUILDINGS', targetSection: 'buildings',
  });
  if (units(capacityRent.arrears) > 0n || capacityRent.status !== 'CURRENT') highlights.push({
    id: `capacity-rent:${summaryDay}`,
    severity: units(capacityRent.arrears) > 0n ? 'high' : 'warning',
    title: 'Capacity rent requires attention',
    reason: `Capacity rent was assessed at ${formatCreditUnits(units(capacityRent.assessed))} CREDIT; ${formatCreditUnits(units(capacityRent.arrears))} CREDIT remains in arrears.`,
    actionLabel: 'REVIEW FINANCE', targetSection: 'finance',
  });
  for (const alert of notifications.rows as Array<Record<string, unknown>>) {
    const type = String(alert.notification_type ?? '').toLowerCase();
    if (!/(failed|overdue|inactive|expired|risk|urgent|required|shortage)/.test(type)) continue;
    highlights.push({
      id: `alert:${alert.id}`, severity: 'high', title: String(alert.title ?? 'House alert'),
      reason: String(alert.body ?? ''), actionLabel: 'OPEN ALERTS', targetSection: 'notifications',
    });
  }

  return {
    version: 2,
    currentGameDay,
    summaryDay,
    financial: {
      incomeUnits: income.toString(),
      expensesUnits: expenses.toString(),
      netCashflowUnits: (income - expenses).toString(),
      cashflowBreakdown,
      ...(capacityRow ? { capacityRent } : {}),
    },
    statement: statementView,
    statementMetadata,
    timeline: eventList,
    resourceShortfallCount,
    resources: { produced: resourceDeltas.filter((item) => units(item.producedUnits) > 0n), consumed: resourceDeltas.filter((item) => units(item.consumedUnits) > 0n), deltas: resourceDeltas },
    marketActivity: market.rows.map((row) => ({
      commodity: row.commodity,
      boughtUnits: unitString(row.bought_units),
      soldUnits: unitString(row.sold_units),
      creditSpentUnits: unitString(row.credit_spent_units),
      creditReceivedUnits: unitString(row.credit_received_units),
      volumeUnits: unitString(row.volume_units),
    })),
    buildings: {
      operatedBuildingCount: Number(operatedBuildings.rows[0]?.count ?? 0),
      completed: buildings.filter((event) => event.type.includes('COMPLETED')),
      upgraded: buildings.filter((event) => event.type.includes('UPGRADED')),
      inactive: buildings.filter((event) => event.type.includes('INACTIVE')),
    },
    research: { progress: research.filter((event) => !event.type.includes('COMPLETED')), completed: research.filter((event) => event.type.includes('COMPLETED')) },
    governance: { eventCount: governance.length, events: governance },
    house: { events: houseEvents },
    alerts,
    highlights,
  };
}
