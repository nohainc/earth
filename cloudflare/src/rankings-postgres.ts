import type { PostgresRepository } from './repository.ts';
import { RANKING_DEFINITIONS, RANKING_METRICS, RANKING_RULES_VERSION, type RankingMetric, type RankingSubjectType } from './rankings.ts';

type RankingCursor = { metric: RankingMetric; search: string | null; value: string; subjectId: string };

function encodeRankingCursor(cursor: RankingCursor): string {
  return btoa(JSON.stringify(cursor));
}

function decodeRankingCursor(value: string | undefined): RankingCursor | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value)) as Partial<RankingCursor>;
    if (!parsed.metric || !(RANKING_METRICS as readonly string[]).includes(parsed.metric) ||
        typeof parsed.value !== 'string' || typeof parsed.subjectId !== 'string' ||
        (parsed.search !== null && typeof parsed.search !== 'string')) return null;
    return { metric: parsed.metric as RankingMetric, search: parsed.search ?? null, value: parsed.value, subjectId: parsed.subjectId };
  } catch {
    return null;
  }
}

const METRIC_SQL: Record<RankingMetric, string> = {
  LIQUID_CREDIT: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(credit.balance_units,0)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry o ON o.id=h.id LEFT JOIN (SELECT a.owner_economic_id, SUM(a.balance_units) AS balance_units FROM economic_accounts a JOIN economic_assets asset ON asset.id=a.asset_id WHERE asset.code='CREDIT' AND a.status='ACTIVE' GROUP BY a.owner_economic_id) credit ON credit.owner_economic_id=o.economic_id WHERE h.status='ACTIVE'`,
  PRODUCTIVE_CAPACITY: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(SUM(bc.slot_footprint),0)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry o ON o.id=h.id LEFT JOIN buildings b ON b.owner_economic_id=o.economic_id AND b.status='ACTIVE' LEFT JOIN building_catalog bc ON bc.id=b.catalog_id WHERE h.status='ACTIVE' GROUP BY h.id,h.house_name`,
  LEGACY: `SELECT id AS subject_id, house_name AS subject_name, dynasty_legacy::NUMERIC AS value FROM houses WHERE status='ACTIVE'`,
  TECHNOLOGY: `SELECT h.id AS subject_id, h.house_name AS subject_name, COUNT(DISTINCT p.id)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry ho ON ho.id=h.id LEFT JOIN technology_patents p ON p.owner_economic_id=ho.economic_id AND p.status='ACTIVE' GROUP BY h.id,h.house_name`,
  PUBLIC_GOODS: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(SUM(CASE WHEN i.id IS NOT NULL THEN c.amount_units ELSE 0 END),0)::NUMERIC AS value FROM houses h LEFT JOIN initiative_contributions c ON c.house_id=h.id AND c.status='APPLIED' LEFT JOIN v5_initiatives i ON i.id=c.initiative_id AND i.status='COMPLETED' WHERE h.status='ACTIVE' GROUP BY h.id,h.house_name`,
  MARKET_VOLUME_30D: `SELECT h.id AS subject_id, h.house_name AS subject_name, COALESCE(volume.credit_units,0)::NUMERIC AS value FROM houses h LEFT JOIN owner_registry o ON o.id=h.id LEFT JOIN (SELECT participant_economic_id, SUM(gross_quote_units) AS credit_units FROM (SELECT f.buyer_economic_id AS participant_economic_id, f.gross_quote_units, b.game_day FROM market_fills f JOIN market_batches b ON b.id=f.batch_id AND b.status='COMPLETED' JOIN market_instruments mi ON mi.id=f.instrument_id JOIN economic_assets qa ON qa.id=mi.quote_asset_id AND qa.code='CREDIT' UNION ALL SELECT f.seller_economic_id AS participant_economic_id, f.gross_quote_units, b.game_day FROM market_fills f JOIN market_batches b ON b.id=f.batch_id AND b.status='COMPLETED' JOIN market_instruments mi ON mi.id=f.instrument_id JOIN economic_assets qa ON qa.id=mi.quote_asset_id AND qa.code='CREDIT') activity WHERE activity.game_day BETWEEN ($1 - 29) AND $1 GROUP BY participant_economic_id) volume ON volume.participant_economic_id=o.economic_id WHERE h.status='ACTIVE' GROUP BY h.id,h.house_name`,
  CORPORATION_MEMBER_HOUSES: `SELECT c.id AS subject_id, i.name AS subject_name, COUNT(DISTINCT ha.house_id)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN house_affiliations ha ON ha.corporation_id=c.id AND ha.status='ACTIVE' WHERE c.status='ACTIVE' GROUP BY c.id,i.name`,
  CORPORATION_LIQUID_CREDIT: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(credit.balance_units,0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN owner_registry o ON o.id=c.id LEFT JOIN (SELECT a.owner_economic_id, SUM(a.balance_units) AS balance_units FROM economic_accounts a JOIN economic_assets asset ON asset.id=a.asset_id WHERE asset.code='CREDIT' AND a.status='ACTIVE' GROUP BY a.owner_economic_id) credit ON credit.owner_economic_id=o.economic_id WHERE c.status='ACTIVE'`,
  CORPORATION_TREASURY: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(SUM(CASE WHEN asset.code='CREDIT' THEN a.balance_units ELSE 0 END),0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN owner_registry o ON o.id=c.id LEFT JOIN economic_accounts a ON a.owner_economic_id=o.economic_id AND a.account_type='TREASURY' AND a.status='ACTIVE' LEFT JOIN economic_assets asset ON asset.id=a.asset_id WHERE c.status='ACTIVE' GROUP BY c.id,i.name`,
  CORPORATION_OCCUPIED_CAPACITY: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(state.total_occupied_units,0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN LATERAL (SELECT total_occupied_units FROM corporation_capacity_state_v5 WHERE corporation_id=c.id ORDER BY game_day DESC LIMIT 1) state ON TRUE WHERE c.status='ACTIVE'`,
  CORPORATION_CAPACITY: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(SUM(CASE WHEN bc.ownership_scope='PUBLIC' THEN bc.slot_footprint ELSE 0 END),0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN owner_registry o ON o.id=c.id LEFT JOIN buildings b ON b.owner_economic_id=o.economic_id AND b.status='ACTIVE' LEFT JOIN building_catalog bc ON bc.id=b.catalog_id WHERE c.status='ACTIVE' GROUP BY c.id,i.name`,
  CORPORATION_SERVICE_CAPACITY: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(snapshot.service_capacity_units,0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN LATERAL (SELECT service_capacity_units FROM corporation_operating_snapshots WHERE corporation_id=c.id ORDER BY game_day DESC LIMIT 1) snapshot ON TRUE WHERE c.status='ACTIVE'`,
  CORPORATION_FISCAL_HEADROOM: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(GREATEST(snapshot.budget_authorized_units - snapshot.budget_committed_units - snapshot.budget_spent_units,0),0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN LATERAL (SELECT budget_authorized_units, budget_committed_units, budget_spent_units FROM institution_financial_snapshots WHERE institution_id=c.id ORDER BY game_day DESC LIMIT 1) snapshot ON TRUE WHERE c.status='ACTIVE' GROUP BY c.id,i.name,snapshot.budget_authorized_units,snapshot.budget_committed_units,snapshot.budget_spent_units`,
  CORPORATION_TECHNOLOGY: `SELECT c.id AS subject_id, i.name AS subject_name, COUNT(DISTINCT a.technology_id)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN owner_registry o ON o.id=c.id LEFT JOIN corporation_technology_access a ON a.corporation_economic_id=o.economic_id AND a.status='ACTIVE' WHERE c.status='ACTIVE' GROUP BY c.id,i.name`,
  CORPORATION_MARKET_VOLUME_30D: `SELECT c.id AS subject_id, i.name AS subject_name, COALESCE(volume.credit_units,0)::NUMERIC AS value FROM corporations c JOIN institutions i ON i.id=c.id LEFT JOIN owner_registry o ON o.id=c.id LEFT JOIN (SELECT participant_economic_id, SUM(gross_quote_units) AS credit_units FROM (SELECT f.buyer_economic_id AS participant_economic_id, f.gross_quote_units, b.game_day FROM market_fills f JOIN market_batches b ON b.id=f.batch_id AND b.status='COMPLETED' JOIN market_instruments mi ON mi.id=f.instrument_id JOIN economic_assets qa ON qa.id=mi.quote_asset_id AND qa.code='CREDIT' UNION ALL SELECT f.seller_economic_id AS participant_economic_id, f.gross_quote_units, b.game_day FROM market_fills f JOIN market_batches b ON b.id=f.batch_id AND b.status='COMPLETED' JOIN market_instruments mi ON mi.id=f.instrument_id JOIN economic_assets qa ON qa.id=mi.quote_asset_id AND qa.code='CREDIT') activity WHERE activity.game_day BETWEEN ($1 - 29) AND $1 GROUP BY participant_economic_id) volume ON volume.participant_economic_id=o.economic_id WHERE c.status='ACTIVE' GROUP BY c.id,i.name,volume.credit_units`,
};

const DEFINITION_BY_METRIC = new Map(RANKING_DEFINITIONS.map((definition) => [definition.code, definition]));

// @mutation-boundary deterministic-settlement: ranking snapshots are keyed by finalized game day and metric.
// @mutation-boundary caller-owned-transaction: ranking projection is refreshed in the settlement phase transaction.
export async function refreshRankingSnapshots(tx: PostgresRepository, gameDay: number) {
  for (const metric of RANKING_METRICS) {
    const snapshotId = `RANKING-${gameDay}-${metric}`;
    await tx.query('INSERT INTO ranking_snapshots (id, metric_code, scope, game_day, rules_version) VALUES ($1,$2,\'GLOBAL\',$3,$4) ON CONFLICT (metric_code, scope, game_day) DO NOTHING', [snapshotId, metric, gameDay, RANKING_RULES_VERSION]);
    const metricParams = (metric === 'MARKET_VOLUME_30D' || metric === 'CORPORATION_MARKET_VOLUME_30D') ? [gameDay] : [];
    const definition = DEFINITION_BY_METRIC.get(metric)!;
    const sourceSql = METRIC_SQL[metric];
    // The latest projection is the complete population. The snapshot below is
    // only a bounded cache for history and fast top-of-leaderboard reads.
    await tx.query('DELETE FROM latest_ranking_metric_values WHERE metric_code = $1', [metric]);
    await tx.query(
      `INSERT INTO latest_ranking_metric_values
         (metric_code, subject_type, subject_id, subject_name, metric_value, game_day, rules_version)
       SELECT '${metric}', '${definition.subjectType}', subject_id, subject_name, value, ${gameDay}, '${RANKING_RULES_VERSION}'
         FROM (${sourceSql}) latest_values`,
      metricParams,
    );
    const rows = (await tx.query<{ rank: string; subject_id: string; subject_name: string; value: string }>(
      `SELECT ROW_NUMBER() OVER (ORDER BY metric_value DESC, subject_id)::TEXT AS rank,
              subject_id, subject_name, metric_value::TEXT AS value
         FROM latest_ranking_metric_values
        WHERE metric_code = $1 AND game_day = $2
        ORDER BY metric_value DESC, subject_id
        LIMIT 100`, [metric, gameDay])).rows;
    await tx.query('DELETE FROM ranking_snapshot_entries WHERE snapshot_id = $1', [snapshotId]);
    for (const row of rows) await tx.query('INSERT INTO ranking_snapshot_entries (snapshot_id, rank, subject_type, subject_id, subject_name, metric_value) VALUES ($1,$2,$3,$4,$5,$6)', [snapshotId, row.rank, definition.subjectType, row.subject_id, row.subject_name, row.value]);
  }
  return { ok: true, gameDay, metricCount: RANKING_METRICS.length };
}

export async function listRankings(repository: PostgresRepository, options: { subjectType?: RankingSubjectType; metric?: string; search?: string; limit?: number; offset?: number; cursor?: string; currentHumanId?: string } = {}) {
  const subjectType = options.subjectType ?? 'HOUSE';
  const metric = options.metric?.toUpperCase();
  const metrics = (metric && (RANKING_METRICS as readonly string[]).includes(metric)
    ? [metric as RankingMetric]
    : RANKING_METRICS.filter((candidate) => DEFINITION_BY_METRIC.get(candidate)?.subjectType === subjectType));
  if (metric && (!DEFINITION_BY_METRIC.has(metric as RankingMetric) || DEFINITION_BY_METRIC.get(metric as RankingMetric)?.subjectType !== subjectType)) {
    throw new Error(`Metric ${metric} is not available for subjectType ${subjectType}`);
  }
  const limit = Math.min(100, Math.max(1, options.limit ?? 50));
  const offset = Math.max(0, options.offset ?? 0);
  const cursor = decodeRankingCursor(options.cursor);
  if (options.cursor && !cursor) throw new Error('Invalid rankings cursor');
  if (cursor && (metrics.length !== 1 || cursor.metric !== metrics[0] || cursor.search !== (options.search ?? null))) {
    throw new Error('Rankings cursor does not match the requested metric or search');
  }
  const latest = await repository.query<{ game_day: string }>('SELECT COALESCE(MAX(game_day),0)::TEXT AS game_day FROM latest_ranking_metric_values');
  const gameDay = Number(latest.rows[0]?.game_day ?? 0);
  const population = await repository.query<{ count: string }>(subjectType === 'HOUSE'
    ? "SELECT COUNT(*)::TEXT AS count FROM houses WHERE status = 'ACTIVE'"
    : "SELECT COUNT(*)::TEXT AS count FROM corporations WHERE status = 'ACTIVE'");
  const actorPopulationSize = Number(population.rows[0]?.count ?? 0);
  const result: Record<string, unknown[]> = {};
  const nextCursors: Record<string, string | null> = {};
  const viewerRanks: Record<string, number | null> = {};
  const viewerValues: Record<string, string | null> = {};
  const populationSizes: Record<string, number> = {};
  const typedItemsByMetric: Record<string, unknown[]> = {};
  let viewerSubjectId: string | null = null;
  let viewerRankDeltaForResponse: number | null = null;
  let viewerValueDeltaForResponse: string | null = null;
  for (const selected of metrics) {
    const definition = DEFINITION_BY_METRIC.get(selected)!;
    const metricPopulation = await repository.query<{ count: string }>(
      'SELECT COUNT(*)::TEXT AS count FROM latest_ranking_metric_values WHERE metric_code = $1 AND subject_type = $2 AND game_day = $3', [selected, subjectType, gameDay]);
    populationSizes[selected] = Number(metricPopulation.rows[0]?.count ?? 0);
    const rows = await repository.query(`
      WITH ranked AS (
        SELECT ROW_NUMBER() OVER (ORDER BY metric_value DESC, subject_id)::TEXT AS rank,
               subject_id, subject_name, metric_value::TEXT AS metric_value
          FROM latest_ranking_metric_values
         WHERE metric_code = $1 AND subject_type = $2 AND game_day = $3
      )
      SELECT rank, subject_id, subject_name, metric_value
        FROM ranked
       WHERE ($4::TEXT IS NULL OR subject_name ILIKE $4)
         AND ($5::NUMERIC IS NULL OR (metric_value::NUMERIC, subject_id) < ($5::NUMERIC, $6::TEXT))
       ORDER BY rank
       LIMIT $7 OFFSET $8`, [selected, subjectType, gameDay, options.search ? `%${options.search}%` : null, cursor?.value ?? null, cursor?.subjectId ?? null, limit + 1, cursor ? 0 : offset]);
    const viewerSubject = options.currentHumanId && definition.subjectType === 'HOUSE'
      ? await repository.query<{ subject_id: string }>('SELECT house_id AS subject_id FROM humans WHERE id = $1', [options.currentHumanId])
      : options.currentHumanId
        ? await repository.query<{ subject_id: string }>(`SELECT ha.corporation_id AS subject_id FROM humans h JOIN house_affiliations ha ON ha.house_id=h.house_id AND ha.status='ACTIVE' WHERE h.id = $1 ORDER BY ha.joined_game_day ASC, ha.corporation_id LIMIT 1`, [options.currentHumanId])
        : { rows: [] };
    viewerSubjectId = viewerSubject.rows[0]?.subject_id ?? null;
    const viewer = viewerSubject.rows[0]?.subject_id
      ? await repository.query<{ rank: string; metric_value: string }>(`
          SELECT rank, metric_value FROM (
            SELECT ROW_NUMBER() OVER (ORDER BY metric_value DESC, subject_id)::TEXT AS rank, subject_id, metric_value::TEXT AS metric_value
              FROM latest_ranking_metric_values
             WHERE metric_code = $1 AND game_day = $2 AND subject_type = $3
          ) ranked
          WHERE subject_id = $4`, [selected, gameDay, definition.subjectType, viewerSubject.rows[0].subject_id])
      : { rows: [] };
    viewerRanks[selected] = viewer.rows[0]?.rank == null ? null : Number(viewer.rows[0].rank);
    viewerValues[selected] = viewer.rows[0]?.metric_value == null ? null : String(viewer.rows[0].metric_value);
    const viewerPrevious = viewerSubject.rows[0]?.subject_id
      ? await repository.query<{ rank: string; metric_value: string }>(`
          SELECT rank, metric_value FROM (
            SELECT ROW_NUMBER() OVER (ORDER BY metric_value DESC, subject_id)::TEXT AS rank,
                   subject_id, metric_value::TEXT AS metric_value
              FROM latest_ranking_metric_values
             WHERE metric_code = $1 AND subject_type = $2
               AND game_day = (SELECT MAX(game_day) FROM latest_ranking_metric_values
                                WHERE metric_code = $1 AND subject_type = $2 AND game_day < $3)
          ) ranked
          WHERE subject_id = $4`, [selected, definition.subjectType, gameDay, viewerSubject.rows[0].subject_id])
      : { rows: [] };
    const viewerRankDelta = viewer.rows[0]?.rank != null && viewerPrevious.rows[0]?.rank != null
      ? Number(viewerPrevious.rows[0].rank) - Number(viewer.rows[0].rank)
      : null;
    const viewerValueDelta = viewer.rows[0]?.metric_value != null && viewerPrevious.rows[0]?.metric_value != null
      ? (() => { try { return (BigInt(String(viewer.rows[0].metric_value)) - BigInt(String(viewerPrevious.rows[0].metric_value))).toString(); } catch { return null; } })()
      : null;
    viewerRankDeltaForResponse = viewerRankDelta;
    viewerValueDeltaForResponse = viewerValueDelta;
    const pageRows = rows.rows.slice(0, limit);
    const last = pageRows.at(-1);
    nextCursors[selected] = rows.rows.length > limit && last
      ? encodeRankingCursor({ metric: selected, search: options.search ?? null, value: String(last.metric_value), subjectId: String(last.subject_id) })
      : null;
    const priorRanks = pageRows.length > 0
      ? await repository.query<{ subject_id: string; rank: string; metric_value: string }>(`
          SELECT e.subject_id, e.rank::TEXT AS rank, e.metric_value::TEXT AS metric_value
            FROM ranking_snapshot_entries e
            JOIN ranking_snapshots s ON s.id=e.snapshot_id
           WHERE s.metric_code = $1 AND s.scope = 'GLOBAL' AND s.subject_type = $2
             AND s.game_day = (SELECT MAX(game_day) FROM ranking_snapshots WHERE metric_code = $1 AND scope = 'GLOBAL' AND subject_type = $2 AND game_day < $3)
             AND e.subject_id = ANY($4::TEXT[])`, [selected, subjectType, gameDay, pageRows.map((row) => String(row.subject_id))])
      : { rows: [] };
    const priorRankBySubject = new Map(priorRanks.rows.map((row) => [String(row.subject_id), Number(row.rank)]));
    const priorValueBySubject = new Map(priorRanks.rows.map((row) => [String(row.subject_id), String(row.metric_value)]));
    const valueDelta = (current: string, prior?: string | null) => {
      if (prior == null) return null;
      try { return (BigInt(current) - BigInt(prior)).toString(); } catch { return null; }
    };
    const items = pageRows.map((row) => ({
      subjectType,
      subjectId: String(row.subject_id),
      subjectName: String(row.subject_name),
      rank: Number(row.rank),
      metricValue: String(row.metric_value),
      metricValueType: definition.valueType,
      topPercent: populationSizes[selected] > 0 ? (Number(row.rank) / populationSizes[selected]) * 100 : null,
      rankDelta: priorRankBySubject.has(String(row.subject_id)) ? (priorRankBySubject.get(String(row.subject_id))! - Number(row.rank)) : null,
      valueDelta: valueDelta(String(row.metric_value), priorValueBySubject.get(String(row.subject_id))),
      populationSize: populationSizes[selected],
    }));
    result[selected] = items.map((item) => ({
      ...item,
      // Compatibility fields remain only inside the legacy metrics map.
      rank: item.rank,
      subject_id: item.subjectId,
      subject_name: item.subjectName,
      metric_value: item.metricValue,
      metric_value_type: item.metricValueType,
      metricValueType: item.metricValueType,
      value_delta: item.valueDelta,
      valueDelta: item.valueDelta,
      population_size: item.populationSize,
      percentile: actorPopulationSize > 0 ? Math.max(0, Math.min(100, ((actorPopulationSize - item.rank + 1) / actorPopulationSize) * 100)) : null,
    }));
    typedItemsByMetric[selected] = items;
  }
  // Keep the legacy top-level collections as compatibility projections for
  // existing clients; V4 consumers use `metrics` and never infer a composite.
  return {
    ok: true,
    rulesVersion: RANKING_RULES_VERSION,
    gameDay,
    subjectType,
    populationSize: metrics.length === 1 ? populationSizes[metrics[0]] : actorPopulationSize,
    populationSizes,
    metrics: result,
    dimensions: metrics,
    nextCursors,
    viewerRanks,
    viewerPosition: metrics.length === 1 ? { subjectType, metric: metrics[0], subjectId: viewerSubjectId, rank: viewerRanks[metrics[0]], metricValue: viewerValues[metrics[0]], rankDelta: viewerRankDeltaForResponse, valueDelta: viewerValueDeltaForResponse, populationSize: populationSizes[metrics[0]] } : null,
    items: metrics.length === 1 ? (typedItemsByMetric[metrics[0]] ?? []) : [],
    nextCursor: metrics.length === 1 ? nextCursors[metrics[0]] : null,
    compositeScore: null,
    corporations: [],
    territories: [],
    technologies: [],
    citizens: [],
    houses: [],
    metricDefinitions: RANKING_DEFINITIONS,
    liquidCredit: result.LIQUID_CREDIT ?? [],
    dynasticHouses: result.LEGACY ?? [],
    generatedFrom: 'ranking-snapshots',
  };
}
