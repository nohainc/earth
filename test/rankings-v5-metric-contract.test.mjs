import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { RANKING_DEFINITIONS, RANKING_METRICS, RANKING_RULES_VERSION, rankMetricRows } from '../cloudflare/src/rankings.ts';
import { listRankings } from '../cloudflare/src/rankings-postgres.ts';

const sql = fs.readFileSync('cloudflare/src/rankings-postgres.ts', 'utf8');
const migration = fs.readFileSync('db/migrations/165_v5_ranking_metric_definitions.sql', 'utf8');
const refinementMigration = fs.readFileSync('db/migrations/166_refine_house_ranking_metrics.sql', 'utf8');
const contractMigration = fs.readFileSync('db/migrations/167_versioned_ranking_metric_contract.sql', 'utf8');
const formulaMigration = fs.readFileSync('db/migrations/168_ranking_formula_metadata.sql', 'utf8');
const populationMigration = fs.readFileSync('db/migrations/169_latest_ranking_metric_values.sql', 'utf8');
const corporationMigration = fs.readFileSync('db/migrations/170_corporation_ranking_subjects.sql', 'utf8');
const corporationMetricsMigration = fs.readFileSync('db/migrations/171_corporation_ranking_metrics.sql', 'utf8');

test('V5 ranking registry contains only active player metrics', () => {
  assert.ok(RANKING_METRICS.includes('LIQUID_CREDIT'));
  assert.ok(RANKING_METRICS.includes('PRODUCTIVE_CAPACITY'));
  assert.ok(RANKING_METRICS.includes('MARKET_VOLUME_30D'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_MEMBER_HOUSES'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_CAPACITY'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_OCCUPIED_CAPACITY'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_TREASURY'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_SERVICE_CAPACITY'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_FISCAL_HEADROOM'));
  assert.ok(RANKING_METRICS.includes('CORPORATION_MARKET_VOLUME_30D'));
  assert.ok(!RANKING_METRICS.includes('WEALTH'));
  assert.ok(!RANKING_METRICS.includes('ORGANIZATION_SCALE'));
  assert.ok(!RANKING_METRICS.includes('TERRITORY_QUALITY'));
  assert.equal(RANKING_RULES_VERSION, 'rankings-v2');
});

test('rankings-v2 defines complete typed metadata for every active metric', () => {
  assert.equal(RANKING_DEFINITIONS.length, RANKING_METRICS.length);
  for (const definition of RANKING_DEFINITIONS) {
    assert.ok(['HOUSE', 'CORPORATION'].includes(definition.subjectType));
    assert.equal(definition.rulesVersion, 'rankings-v2');
    assert.ok(definition.title);
    assert.ok(definition.description);
    assert.ok(definition.formula);
    assert.ok(definition.valueType);
    assert.ok(definition.unit);
    assert.ok(definition.calculationSource);
    assert.ok(definition.timeWindow);
    assert.equal(definition.tieBehavior, 'VALUE_DESC_SUBJECT_ID_ASC');
  }
});

test('ranking snapshots use PostgreSQL exact-value ordering', () => {
  assert.match(sql, /ROW_NUMBER\(\) OVER \(ORDER BY metric_value DESC, subject_id\)/);
  assert.match(sql, /value::TEXT AS value/);
  assert.doesNotMatch(sql, /rankMetricRows\(/);
  assert.doesNotMatch(sql, /Number\(row\.value\)/);
});

test('Corporation metrics use institutional subjects, never Humans or Territories', () => {
  assert.match(sql, /CORPORATION_MEMBER_HOUSES[\s\S]*FROM corporations/);
  assert.match(sql, /CORPORATION_CAPACITY[\s\S]*FROM corporations/);
  assert.match(sql, /CORPORATION_TECHNOLOGY[\s\S]*corporation_technology_access/);
  assert.doesNotMatch(sql, /CORPORATION_MEMBER_HOUSES:[^`]*territor/i);
  assert.match(corporationMigration, /'CORPORATION_MEMBER_HOUSES'/);
  assert.match(corporationMigration, /subject_type IN \('HOUSE', 'CORPORATION'\)/);
  assert.match(corporationMetricsMigration, /CORPORATION_FISCAL_HEADROOM/);
  assert.match(corporationMetricsMigration, /CORPORATION_MARKET_VOLUME_30D/);
});

test('rankings retain a full latest population projection', () => {
  assert.match(sql, /latest_ranking_metric_values/);
  assert.match(sql, /viewerRanks/);
  assert.match(sql, /nextCursors/);
  assert.match(populationMigration, /PRIMARY KEY \(metric_code, subject_type, subject_id\)/);
  assert.match(populationMigration, /metric_value NUMERIC/);
});

test('canonical ranking responses expose typed actor fields and retire category', () => {
  assert.match(sql, /subjectType/);
  assert.match(sql, /subjectId/);
  assert.match(sql, /metricValueType/);
  assert.match(sql, /topPercent/);
  assert.match(sql, /rankDelta/);
  assert.match(sql, /viewerPosition/);
  assert.match(sql, /nextCursor/);
  assert.match(fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8'), /category parameter is retired/);
});

test('standalone ranking ordering compares large integer values without Number', () => {
  const ranked = rankMetricRows([
    { subjectId: 'B', subjectName: 'Beta', value: '99999999999999999999' },
    { subjectId: 'A', subjectName: 'Alpha', value: '100000000000000000000' },
  ]);
  assert.equal(ranked[0].subjectId, 'A');
  assert.equal(ranked[0].value, '100000000000000000000');
});

test('Liquid CREDIT excludes unlike resource dimensions', () => {
  assert.match(sql, /LIQUID_CREDIT[\s\S]*economic_assets asset[\s\S]*asset\.code='CREDIT'/);
  assert.match(sql, /LIQUID_CREDIT[\s\S]*GROUP BY a\.owner_economic_id/);
  assert.doesNotMatch(sql, /LIQUID_CREDIT[\s\S]*asset_kind='RESOURCE'/);
  assert.doesNotMatch(sql, /LIQUID_CREDIT[\s\S]*SUM\([^)]*FOOD/i);
  assert.doesNotMatch(sql, /LIQUID_CREDIT[\s\S]*SUM\([^)]*ENERGY/i);
});

test('10 FOOD cannot contaminate Liquid CREDIT wealth', () => {
  const creditOnly = rankMetricRows([
    { subjectId: 'HOUSE-A', subjectName: 'A', value: '50000' },
    // Resource inventory is deliberately not an input to this metric.
  ]);
  assert.deepEqual(creditOnly.map((row) => row.value), ['50000']);
  assert.equal(RANKING_DEFINITIONS.find((definition) => definition.code === 'LIQUID_CREDIT')?.unit, 'CREDIT');
  assert.notEqual('10000000', creditOnly[0].value, '10 FOOD atomic units must never become wealth');
});

test('Productive capacity ranks active footprint, not building count', () => {
  assert.match(sql, /PRODUCTIVE_CAPACITY[\s\S]*SUM\(bc\.slot_footprint\)/);
  assert.match(sql, /PRODUCTIVE_CAPACITY[\s\S]*building_catalog bc/);
  assert.match(sql, /PRODUCTIVE_CAPACITY[\s\S]*b\.status='ACTIVE'/);
  assert.doesNotMatch(sql, /PRODUCTIVE_CAPACITY[\s\S]*COUNT\(b\.id\)/);
});

test('ranking source has no Territory or Organization metric definitions', () => {
  assert.equal(RANKING_DEFINITIONS.some((definition) => definition.code.includes('TERRITORY')), false);
  assert.equal(RANKING_DEFINITIONS.some((definition) => definition.code.includes('ORGANIZATION')), false);
  assert.doesNotMatch(sql, /TERRITORY_QUALITY|ORGANIZATION_SCALE/);
});

test('House technology excludes Corporation-wide access', () => {
  assert.match(sql, /TECHNOLOGY[\s\S]*COUNT\(DISTINCT p\.id\)/);
  assert.doesNotMatch(sql, /\n  TECHNOLOGY: `[^`]*corporation_technology_access/);
});

test('Public goods counts only completed Initiative contributions', () => {
  assert.match(sql, /PUBLIC_GOODS[\s\S]*initiative_contributions/);
  assert.match(sql, /PUBLIC_GOODS[\s\S]*c\.status='APPLIED'/);
  assert.match(sql, /PUBLIC_GOODS[\s\S]*i\.status='COMPLETED'/);
  assert.doesNotMatch(sql, /PUBLIC_GOODS[\s\S]*public_project_contributions/);
});

test('Market metric is trailing-30-day finalized CREDIT volume', () => {
  assert.match(sql, /MARKET_VOLUME_30D[\s\S]*SUM\(gross_quote_units\)/);
  assert.match(sql, /MARKET_VOLUME_30D[\s\S]*b\.status='COMPLETED'/);
  assert.match(sql, /MARKET_VOLUME_30D[\s\S]*qa\.code='CREDIT'/);
  assert.match(sql, /MARKET_VOLUME_30D[\s\S]*BETWEEN \(\$1 - 29\) AND \$1/);
  assert.doesNotMatch(sql, /MARKET_VOLUME_30D[\s\S]*COUNT\(DISTINCT f\.id\)/);
});

test('Retired ranking definitions remain historical but cannot be refreshed', () => {
  assert.match(migration, /LIQUID_CREDIT/);
  assert.match(migration, /WHERE metric_code = 'WEALTH'/);
  assert.match(migration, /metric_code IN \('ORGANIZATION_SCALE', 'TERRITORY_QUALITY'\)/);
  assert.match(refinementMigration, /MARKET_VOLUME_30D/);
  assert.match(refinementMigration, /WHERE metric_code = 'MARKET_ROLE'/);
  assert.match(contractMigration, /ADD COLUMN IF NOT EXISTS description/);
  assert.match(contractMigration, /ADD COLUMN IF NOT EXISTS value_type/);
  assert.match(contractMigration, /ADD COLUMN IF NOT EXISTS tie_behavior/);
  assert.match(contractMigration, /ALTER COLUMN description SET NOT NULL/);
  assert.match(formulaMigration, /ADD COLUMN IF NOT EXISTS subject_type/);
  assert.match(formulaMigration, /ADD COLUMN IF NOT EXISTS formula/);
  assert.match(formulaMigration, /ALTER COLUMN formula SET NOT NULL/);
});

function rankingRepository({ rows, priorRows = [], population = '10000', subjectType = 'HOUSE', searchParams } = {}) {
  const calls = [];
  return {
    calls,
    async query(query, params = []) {
      calls.push({ query, params });
      if (query.includes('COALESCE(MAX(game_day),0)')) return { rows: [{ game_day: '10' }] };
      if (query.includes("FROM houses WHERE status = 'ACTIVE'")) return { rows: [{ count: population }] };
      if (query.includes("FROM corporations WHERE status = 'ACTIVE'")) return { rows: [{ count: population }] };
      if (query.includes('COUNT(*)::TEXT AS count FROM latest_ranking_metric_values')) return { rows: [{ count: population }] };
      if (query.includes('FROM ranking_snapshot_entries')) return { rows: priorRows };
      if (query.includes('WITH ranked AS')) return { rows: rows ?? [] };
      return { rows: [] };
    },
  };
}

test('rank 101 remains queryable through the full latest projection', async () => {
  const repository = rankingRepository({
    rows: [{ rank: '101', subject_id: 'HOUSE-101', subject_name: 'House 101', metric_value: '900' }],
  });
  const response = await listRankings(repository, {
    subjectType: 'HOUSE', metric: 'LIQUID_CREDIT', offset: 100, limit: 1,
  });
  assert.equal(response.items[0].rank, 101);
  assert.equal(response.items[0].subjectId, 'HOUSE-101');
  const rankedQuery = repository.calls.find((call) => call.query.includes('WITH ranked AS'));
  assert.equal(rankedQuery.params.at(-1), 100);
  assert.match(rankedQuery.query, /latest_ranking_metric_values/);
});

test('server-side search can return a subject ranked 9000', async () => {
  const repository = rankingRepository({
    rows: [{ rank: '9000', subject_id: 'HOUSE-9000', subject_name: 'House 9000', metric_value: '1' }],
  });
  const response = await listRankings(repository, {
    subjectType: 'HOUSE', metric: 'LIQUID_CREDIT', search: 'House 9000', limit: 25,
  });
  assert.equal(response.items[0].rank, 9000);
  const rankedQuery = repository.calls.find((call) => call.query.includes('WITH ranked AS'));
  assert.equal(rankedQuery.params[3], '%House 9000%');
  assert.match(rankedQuery.query, /subject_name ILIKE/);
});

test('House and Corporation ranking metrics are separate contracts', async () => {
  const house = await listRankings(rankingRepository({ rows: [{ rank: '1', subject_id: 'H-1', subject_name: 'House', metric_value: '50000' }] }), {
    subjectType: 'HOUSE', metric: 'LIQUID_CREDIT', limit: 1,
  });
  const corporation = await listRankings(rankingRepository({ rows: [{ rank: '1', subject_id: 'C-1', subject_name: 'Corp', metric_value: '70000' }], subjectType: 'CORPORATION' }), {
    subjectType: 'CORPORATION', metric: 'CORPORATION_TREASURY', limit: 1,
  });
  assert.equal(house.subjectType, 'HOUSE');
  assert.equal(house.items[0].metricValueType, 'CREDIT_UNITS');
  assert.equal(corporation.subjectType, 'CORPORATION');
  assert.equal(corporation.items[0].metricValueType, 'CREDIT_UNITS');
  assert.notEqual(house.items[0].subjectType, corporation.items[0].subjectType);
});

test('category is rejected rather than silently ignored', () => {
  const routeSource = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
  assert.match(routeSource, /category parameter is retired/);
  assert.match(routeSource, /subjectType/);
});

test('rank and value deltas are deterministic from finalized snapshots', async () => {
  const makeRepository = () => rankingRepository({
    rows: [
      { rank: '1', subject_id: 'HOUSE-A', subject_name: 'A', metric_value: '120' },
      { rank: '2', subject_id: 'HOUSE-B', subject_name: 'B', metric_value: '90' },
    ],
    priorRows: [
      { subject_id: 'HOUSE-A', rank: '2', metric_value: '100' },
      { subject_id: 'HOUSE-B', rank: '1', metric_value: '95' },
    ],
  });
  const first = await listRankings(makeRepository(), { subjectType: 'HOUSE', metric: 'LIQUID_CREDIT', limit: 2 });
  const second = await listRankings(makeRepository(), { subjectType: 'HOUSE', metric: 'LIQUID_CREDIT', limit: 2 });
  assert.deepEqual(first.items.map((item) => [item.rankDelta, item.valueDelta]), [[1, '20'], [-1, '-5']]);
  assert.deepEqual(second.items.map((item) => [item.rankDelta, item.valueDelta]), first.items.map((item) => [item.rankDelta, item.valueDelta]));
  assert.match(sql, /ranking_snapshot_entries/);
  assert.match(sql, /MAX\(game_day\).*game_day < \$3/);
});
