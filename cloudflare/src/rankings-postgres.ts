import type { PostgresRepository } from './repository.ts';
import { RANKING_METRICS, RANKING_RULES_VERSION, rankMetricRows, type RankingMetric } from './rankings.ts';

const HOUSE_METRIC_SQL: Record<RankingMetric, string> = {
  WEALTH: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(SUM(a.balance_units),0)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry o ON o.id=h.id LEFT JOIN economic_accounts a ON a.owner_economic_id=o.economic_id AND a.status='ACTIVE' GROUP BY h.id,h.house_name`,
  PRODUCTIVE_CAPACITY: `SELECT h.id AS subject_id, h.house_name AS subject_name, COUNT(b.id)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry o ON o.id=h.id LEFT JOIN buildings b ON b.owner_economic_id=o.economic_id AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION') GROUP BY h.id,h.house_name`,
  LEGACY: `SELECT id AS subject_id, house_name AS subject_name, dynasty_legacy::NUMERIC AS value FROM houses WHERE status='ACTIVE'`,
  TECHNOLOGY: `SELECT h.id AS subject_id, h.house_name AS subject_name, (COUNT(DISTINCT p.id)+COUNT(DISTINCT ca.technology_id))::NUMERIC AS value FROM houses h LEFT JOIN owner_registry ho ON ho.id=h.id LEFT JOIN technology_patents p ON p.owner_economic_id=ho.economic_id AND p.status='ACTIVE' LEFT JOIN house_affiliations ha ON ha.house_id=h.id AND ha.status='ACTIVE' LEFT JOIN owner_registry co ON co.id=ha.corporation_id LEFT JOIN corporation_technology_access ca ON ca.corporation_economic_id=co.economic_id AND ca.status='ACTIVE' GROUP BY h.id,h.house_name`,
  PUBLIC_GOODS: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(SUM(c.amount_units),0)::NUMERIC AS value FROM houses h LEFT JOIN public_project_contributions c ON c.house_id=h.id AND c.status='ESCROWED' GROUP BY h.id,h.house_name`,
  ORGANIZATION_SCALE: `SELECT h.id AS subject_id, h.house_name AS subject_name, COUNT(m.id)::NUMERIC AS value FROM houses h LEFT JOIN organization_memberships m ON m.house_id=h.id AND m.status='ACTIVE' GROUP BY h.id,h.house_name`,
  TERRITORY_QUALITY: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(MAX(s.housing_capacity+s.energy_capacity+s.connectivity_capacity),0)::NUMERIC AS value FROM houses h LEFT JOIN house_residencies r ON r.house_id=h.id AND r.status='ACTIVE' AND r.residency_class='PRIMARY' LEFT JOIN territory_capacity_state s ON s.territory_id=r.territory_id GROUP BY h.id,h.house_name`,
  MARKET_ROLE: `SELECT h.id AS subject_id, h.house_name AS subject_name, COUNT(DISTINCT f.id)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry o ON o.id=h.id LEFT JOIN market_orders bo ON bo.owner_economic_id=o.economic_id LEFT JOIN market_fills f ON f.buy_order_id=bo.id OR f.sell_order_id=bo.id GROUP BY h.id,h.house_name`,
};

// @mutation-boundary deterministic-settlement: ranking snapshots are keyed by finalized game day and metric.
// @mutation-boundary caller-owned-transaction: ranking projection is refreshed in the settlement phase transaction.
export async function refreshRankingSnapshots(tx: PostgresRepository, gameDay: number) {
  for (const metric of RANKING_METRICS) {
    const snapshotId = `RANKING-${gameDay}-${metric}`;
    await tx.query('INSERT INTO ranking_snapshots (id, metric_code, scope, game_day, rules_version) VALUES ($1,$2,\'GLOBAL\',$3,$4) ON CONFLICT (metric_code, scope, game_day) DO NOTHING', [snapshotId, metric, gameDay, RANKING_RULES_VERSION]);
    // The snapshot is intentionally a bounded top-100 projection. Source
    // facts stay in their owning tables; a day close must not scan/write an
    // unbounded leaderboard payload.
    const rows = (await tx.query<{ subject_id: string; subject_name: string; value: string }>(`${HOUSE_METRIC_SQL[metric]} ORDER BY value DESC, subject_id LIMIT 100`)).rows;
    const ranked = rankMetricRows(rows.map((row) => ({ subjectId: row.subject_id, subjectName: row.subject_name, value: row.value })));
    await tx.query('DELETE FROM ranking_snapshot_entries WHERE snapshot_id = $1', [snapshotId]);
    for (const row of ranked) await tx.query('INSERT INTO ranking_snapshot_entries (snapshot_id, rank, subject_type, subject_id, subject_name, metric_value) VALUES ($1,$2,\'HOUSE\',$3,$4,$5)', [snapshotId, row.rank, row.subjectId, row.subjectName, row.value]);
  }
  return { ok: true, gameDay, metricCount: RANKING_METRICS.length };
}

export async function listRankings(repository: PostgresRepository, options: { category?: string; metric?: string; search?: string; limit?: number; offset?: number; currentHumanId?: string } = {}) {
  const metric = options.metric?.toUpperCase();
  const metrics = metric && (RANKING_METRICS as readonly string[]).includes(metric) ? [metric as RankingMetric] : RANKING_METRICS;
  const limit = Math.min(100, Math.max(1, options.limit ?? 50));
  const offset = Math.max(0, options.offset ?? 0);
  const latest = await repository.query<{ game_day: string }>('SELECT COALESCE(MAX(game_day),0)::TEXT AS game_day FROM ranking_snapshots WHERE scope=\'GLOBAL\'');
  const gameDay = Number(latest.rows[0]?.game_day ?? 0);
  const result: Record<string, unknown[]> = {};
  for (const selected of metrics) {
    const rows = await repository.query(`SELECT e.rank, e.subject_id, e.subject_name, e.metric_value::TEXT AS metric_value FROM ranking_snapshot_entries e JOIN ranking_snapshots s ON s.id=e.snapshot_id WHERE s.metric_code=$1 AND s.scope='GLOBAL' AND s.game_day=$2 ${options.search ? 'AND e.subject_name ILIKE $3' : ''} ORDER BY e.rank LIMIT $${options.search ? 4 : 3} OFFSET $${options.search ? 5 : 4}`, options.search ? [selected, gameDay, `%${options.search}%`, limit, offset] : [selected, gameDay, limit, offset]);
    result[selected] = rows.rows;
  }
  // Keep the legacy top-level collections as compatibility projections for
  // existing clients; V4 consumers use `metrics` and never infer a composite.
  return {
    ok: true,
    rulesVersion: RANKING_RULES_VERSION,
    gameDay,
    metrics: result,
    dimensions: metrics,
    compositeScore: null,
    corporations: [],
    territories: [],
    technologies: [],
    citizens: [],
    houses: [],
    wealth: result.WEALTH ?? [],
    dynasticHouses: result.LEGACY ?? [],
    generatedFrom: 'ranking-snapshots',
  };
}
