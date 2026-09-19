import type { PostgresRepository } from './repository.ts';
import { getV5HouseCapacity } from './v5-capacity-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { getDecisionQueue } from './decision-queue-postgres.ts';

/** Convert database bigint values to the JSON wire representation. */
function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)])) as T;
  }
  return value;
}

/**
 * Canonical V5 Command overview. This deliberately contains only persisted
 * facts and server-owned attention items; it does not synthesize objectives,
 * prices, resource balances, or Territory capacity on the client.
 */
export async function getV5Overview(repository: PostgresRepository, houseId: string) {
  const [clock, house, affiliation, wallet, statement, delinquency, buildingCounts, marketRows, decisionQueue] = await Promise.all([
    readAuthoritativeGameTime(repository),
    repository.query<{ id: string; house_name: string; generation: number; status: string }>(
      'SELECT id, house_name, generation, status FROM houses WHERE id = $1', [houseId]),
    repository.query<{ corporation_id: string; status: string }>(
      "SELECT corporation_id, status FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE'", [houseId]),
    repository.query<{ balance_units: string }>(
      `SELECT COALESCE(SUM(a.balance_units), 0)::TEXT AS balance_units
       FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1
         AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [houseId]),
    repository.query(
      `SELECT game_day, opening_assets, closing_assets, net_credit_units
       FROM house_daily_statements WHERE house_id = $1
       ORDER BY game_day DESC LIMIT 1`, [houseId]),
    repository.query<{ status: string; arrears_since_game_day: number | null; consecutive_missed_days: number }>(
      `SELECT status, arrears_since_game_day, consecutive_missed_days
       FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [houseId]),
    repository.query<{ total_count: string; active_count: string; suspended_count: string; other_count: string }>(
      `SELECT
         COUNT(*)::TEXT AS total_count,
         COUNT(*) FILTER (WHERE b.status = 'ACTIVE')::TEXT AS active_count,
         COUNT(*) FILTER (WHERE b.status = 'SUSPENDED')::TEXT AS suspended_count,
         COUNT(*) FILTER (WHERE b.status NOT IN ('ACTIVE', 'SUSPENDED'))::TEXT AS other_count
       FROM buildings b
       JOIN owner_registry o ON o.economic_id = b.owner_economic_id
       WHERE o.id = $1 AND o.owner_type = 'HOUSE'`, [houseId]),
    repository.query<{ product: string; supply: string; demand: string; price: string }>(
      `SELECT LOWER(REPLACE(i.symbol, 'SPOT-', '')) AS product,
              COALESCE(s.open_sell_units, 0)::TEXT AS supply,
              COALESCE(s.open_buy_units, 0)::TEXT AS demand,
              COALESCE(s.last_clearing_price_units, 0)::TEXT AS price
         FROM market_instruments i
         LEFT JOIN market_instrument_state s ON s.instrument_id = i.id
        WHERE i.instrument_type = 'SPOT' AND i.status = 'ACTIVE'
        ORDER BY i.symbol`),
    getDecisionQueue(repository, houseId, 20),
  ]);

  const currentGameDay = clock.gameDay;
  const houseRow = house.rows[0];
  if (!houseRow) throw new Error('House not found');
  const capacity = await getV5HouseCapacity(repository, houseId);
  const delinquencyRow = delinquency.rows[0] ?? {
    status: 'CURRENT', arrears_since_game_day: null, consecutive_missed_days: 0,
  };
  const attention: Array<Record<string, unknown>> = [];
  if (delinquencyRow.status !== 'CURRENT') {
    attention.push({
      id: `v5-capacity-${houseId}`,
      category: 'finance',
      severity: delinquencyRow.status === 'PRODUCTIVE_CAPACITY_SUSPENDED' ? 'critical' : 'high',
      type: 'CAPACITY_RENT',
      title: 'House capacity rent requires attention',
      whyItMatters: 'Unpaid capacity rent can block expansion and eventually suspend productive buildings.',
      deadline: 'Before the next settlement',
      expectedImpact: 'Restore the House to current capacity-rent standing.',
      riskLevel: delinquencyRow.status === 'PRODUCTIVE_CAPACITY_SUSPENDED' ? 'critical' : 'high',
      primaryActionLabel: 'Review Finance',
      status: delinquencyRow.status,
      missedDays: Number(delinquencyRow.consecutive_missed_days ?? 0),
      targetRoute: 'finance',
      viewerCanAct: true,
      urgencyScore: delinquencyRow.status === 'PRODUCTIVE_CAPACITY_SUSPENDED' ? 100 : 90,
    });
  }

  const buildingCountRow = buildingCounts.rows[0] ?? {
    total_count: '0',
    active_count: '0',
    suspended_count: '0',
    other_count: '0',
  };

  const marketProducts = marketRows.rows.map((r) => ({
    product: r.product,
    supplyUnits: r.supply,
    demandUnits: r.demand,
    priceUnits: r.price,
  }));

  const energyPriceUnits = marketRows.rows.find((r) => r.product === 'energy')?.price ?? '0';
  const materialsPriceUnits = marketRows.rows.find((r) => r.product === 'material' || r.product === 'materials')?.price ?? '0';
  const componentsPriceUnits = marketRows.rows.find((r) => r.product === 'component' || r.product === 'components')?.price ?? '0';

  const decisions = decisionQueue.decisions ?? [];
  const criticalCount = decisions.filter((d) => d.riskLevel === 'critical').length;
  const highCount = decisions.filter((d) => d.riskLevel === 'high').length;

  return {
    ok: true,
    version: 'V5-OVERVIEW-1',
    gameDay: currentGameDay,
    nextSettlementGameDay: currentGameDay + 1,
    house: {
      id: houseRow.id,
      name: houseRow.house_name,
      generation: houseRow.generation,
      status: houseRow.status,
      corporationId: affiliation.rows[0]?.corporation_id ?? null,
    },
    capacity: toJsonSafe(capacity),
    finance: {
      availableWalletUnits: wallet.rows[0]?.balance_units ?? '0',
      latestStatement: toJsonSafe(statement.rows[0] ?? null),
    },
    buildings: {
      totalCount: Number(buildingCountRow.total_count),
      activeCount: Number(buildingCountRow.active_count),
      suspendedCount: Number(buildingCountRow.suspended_count),
      otherCount: Number(buildingCountRow.other_count),
    },
    market: {
      energyPriceUnits,
      materialsPriceUnits,
      componentsPriceUnits,
      products: marketProducts,
    },
    decisions: {
      totalCount: decisions.length,
      criticalCount,
      highCount,
      items: decisions,
    },
    attention,
    generatedFrom: 'postgres-canonical-facts-v5',
  };
}
