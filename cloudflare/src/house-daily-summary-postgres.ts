import type { PostgresRepository } from './repository.ts';

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
};

function units(value: unknown): number {
  return Number(value ?? 0);
}

function eventRows(rows: Record<string, unknown>[]): SummaryEvent[] {
  return rows.map((row) => ({
    id: String(row.id),
    type: String(row.event_type),
    title: String(row.title),
    details: row.details == null ? '' : String(row.details),
    gameDay: Number(row.game_day),
    gameMinute: row.game_minute == null ? null : Number(row.game_minute),
  }));
}

function jsonObject(value: unknown): Record<string, string> {
  const parsed = typeof value === 'string' ? JSON.parse(value || '{}') : value;
  return Object.fromEntries(Object.entries((parsed ?? {}) as Record<string, unknown>).map(([key, item]) => [key, String(item)]));
}

export async function getHouseDailySummary(
  repository: PostgresRepository,
  houseId: string,
  requestedDay?: number,
) {
  const world = await repository.query<{ game_day: number }>(
    "SELECT game_day FROM world_state WHERE id = 'WORLD'",
  );
  if (!world.rows[0]) throw new Error('World state is unavailable');

  const currentGameDay = Number(world.rows[0].game_day);
  const summaryDay = requestedDay ?? Math.max(0, currentGameDay - 1);
  if (!Number.isInteger(summaryDay) || summaryDay < 0 || summaryDay >= currentGameDay) {
    throw new Error('Summary day must be a completed game day');
  }

  const [statement, cashflow, taxes, market, events, notifications, capacity] = await Promise.all([
    repository.query(`
      SELECT opening_assets, closing_assets, production, consumption, market_activity,
             obligations, exceptions, net_credit_units
      FROM house_daily_statements WHERE house_id = $1 AND game_day = $2`, [houseId, summaryDay]),
    repository.query(`
      SELECT
        COALESCE(SUM(CASE WHEN net_units > 0 THEN net_units ELSE 0 END), 0)::text AS income,
        COALESCE(SUM(CASE WHEN net_units < 0 THEN -net_units ELSE 0 END), 0)::text AS expenses
      FROM (
        SELECT t.id, SUM(e.delta_units) AS net_units
        FROM economic_transactions t
        JOIN economic_entries e ON e.transaction_id = t.id
        JOIN economic_accounts a ON a.id = e.account_id
        JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        JOIN economic_assets asset ON asset.id = e.asset_id
        WHERE o.id = $1 AND t.game_day = $2 AND asset.code = 'CREDIT'
        GROUP BY t.id
      ) house_transactions`, [houseId, summaryDay]),
    repository.query(`
      SELECT COALESCE(SUM(o.amount_units), 0)::text AS taxes
      FROM tax_obligations o
      JOIN economic_transactions t ON t.id = o.payment_transaction_id
      JOIN owner_registry owner ON owner.id = $1
      WHERE o.taxpayer_economic_id = owner.economic_id AND t.game_day = $2`, [houseId, summaryDay]),
    repository.query(`
      SELECT i.symbol AS commodity,
             COALESCE(SUM(CASE WHEN f.buyer_economic_id = owner.economic_id THEN f.gross_quote_units ELSE 0 END), 0)::text AS purchases,
             COALESCE(SUM(CASE WHEN f.seller_economic_id = owner.economic_id THEN f.gross_quote_units ELSE 0 END), 0)::text AS sales,
             COALESCE(SUM(f.quantity_units), 0)::text AS volume
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
      SELECT id, notification_type, title, body, game_day, game_minute, read_at
      FROM notifications
      WHERE house_id = $1 AND game_day = $2
      ORDER BY created_at, id`, [houseId, summaryDay]),
  ]);

  // V5 is additive while older summary callers can still run against a
  // pre-V5 projection. Keep the optional read isolated so the core summary
  // remains available during rollout and migration catch-up.
  let v5Capacity: { rows: Array<Record<string, unknown>> } = { rows: [] };
  try {
    v5Capacity = await repository.query(`
      SELECT
        COALESCE(SUM(assessed_units), 0)::text AS assessed,
        COALESCE(SUM(paid_units), 0)::text AS paid,
        COALESCE(SUM(arrears_units), 0)::text AS arrears,
        COALESCE(MAX(delinquency_status), 'CURRENT') AS status
      FROM house_capacity_statements_v5
      WHERE house_id = $1 AND game_day = $2`, [houseId, summaryDay]);
  } catch {
    // The V5 migration may not yet be present on an older read replica.
  }

  const financial = cashflow.rows[0] ?? {};
  const income = units(financial.income);
  const expenses = units(financial.expenses);
  const taxUnits = units(taxes.rows[0]?.taxes);
  const capacityRow = v5Capacity.rows[0] as Record<string, unknown> | undefined;
  const capacityRent = {
    assessed: units(capacityRow?.assessed),
    paid: units(capacityRow?.paid),
    arrears: units(capacityRow?.arrears),
    status: String(capacityRow?.status ?? 'CURRENT'),
  };
  const eventList = eventRows(events.rows as Record<string, unknown>[]);
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

  const authoritative = statement.rows[0] as Record<string, unknown> | undefined;
  const production = authoritative ? jsonObject(authoritative.production) : {};
  const consumption = authoritative ? jsonObject(authoritative.consumption) : {};
  const resourceCodes = new Set([...Object.keys(production), ...Object.keys(consumption)]);
  const resourceDeltas = [...resourceCodes].sort().map((resource) => ({
    resource,
    produced: units(production[resource]),
    consumed: units(consumption[resource]),
    net: units(production[resource]) - units(consumption[resource]),
  }));
  const statementView = authoritative ? {
    openingAssets: jsonObject(authoritative.opening_assets),
    closingAssets: jsonObject(authoritative.closing_assets),
    production: jsonObject(authoritative.production),
    consumption: jsonObject(authoritative.consumption),
    marketActivity: authoritative.market_activity ?? {},
    obligations: authoritative.obligations ?? {},
    exceptions: authoritative.exceptions ?? {},
    netCreditUnits: String(authoritative.net_credit_units ?? '0'),
  } : null;

  const highlights: Array<Record<string, unknown>> = [];
  if (expenses > income) highlights.push({
    id: 'negative_cashflow', severity: 'warning', title: 'Expenses exceeded income',
    reason: `Your House spent ${expenses} CREDIT and received ${income} CREDIT on game day ${summaryDay}.`,
    actionLabel: 'REVIEW FINANCE', targetSection: 'finance',
  });
  for (const event of buildings.filter((item) => item.type.includes('INACTIVE'))) highlights.push({
    id: `building-inactive:${event.id}`, severity: 'high', title: event.title,
    reason: event.details, actionLabel: 'VIEW BUILDINGS', targetSection: 'buildings',
  });
  for (const item of resourceDeltas.filter((delta) => delta.net < 0)) highlights.push({
    id: `resource-decline:${item.resource}`, severity: 'warning', title: `${item.resource} decreased`,
    reason: `${item.resource} production was ${item.produced} and consumption was ${item.consumed} on game day ${summaryDay}.`,
    actionLabel: 'REVIEW RESOURCES', targetSection: 'buildings',
  });
  if (capacityRent.arrears > 0 || capacityRent.status !== 'CURRENT') highlights.push({
    id: `capacity-rent:${summaryDay}`,
    severity: capacityRent.arrears > 0 ? 'high' : 'warning',
    title: 'Capacity rent requires attention',
    reason: `Capacity rent was assessed at ${capacityRent.assessed} CREDIT; ${capacityRent.arrears} CREDIT remains in arrears.`,
    actionLabel: 'REVIEW FINANCE', targetSection: 'finance',
  });
  for (const alert of notifications.rows as Array<Record<string, unknown>>) {
    const type = String(alert.notification_type ?? '').toLowerCase();
    if (alert.read_at != null || !/(failed|overdue|inactive|expired|risk|urgent|required|shortage)/.test(type)) continue;
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
      income,
      expenses,
      net: income - expenses,
      taxes: taxUnits,
      marketPurchases: market.rows.reduce((sum, row) => sum + units(row.purchases), 0),
      marketSales: market.rows.reduce((sum, row) => sum + units(row.sales), 0),
      ...(capacityRow ? { capacityRent } : {}),
    },
    statement: statementView,
    resources: { produced: resourceDeltas.filter((item) => item.produced > 0), consumed: resourceDeltas.filter((item) => item.consumed > 0), deltas: resourceDeltas, traded: market.rows.map((row) => ({ commodity: row.commodity, purchases: units(row.purchases), sales: units(row.sales), volume: units(row.volume) })) },
    buildings: { completed: buildings.filter((event) => event.type.includes('COMPLETED')), upgraded: buildings.filter((event) => event.type.includes('UPGRADED')), inactive: buildings.filter((event) => event.type.includes('INACTIVE')) },
    research: { progress: research.filter((event) => !event.type.includes('COMPLETED')), completed: research.filter((event) => event.type.includes('COMPLETED')) },
    governance: { relevantEvents: governance },
    house: { events: houseEvents },
    alerts,
    highlights,
  };
}
