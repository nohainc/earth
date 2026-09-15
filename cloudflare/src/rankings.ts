export const RANKING_RULES_VERSION = 'rankings-v1';

export const RANKING_METRICS = [
  'WEALTH', 'PRODUCTIVE_CAPACITY', 'LEGACY', 'TECHNOLOGY',
  'PUBLIC_GOODS', 'ORGANIZATION_SCALE', 'TERRITORY_QUALITY', 'MARKET_ROLE',
] as const;

export type RankingMetric = typeof RANKING_METRICS[number];

export function rankMetricRows(rows: Array<{ subjectId: string; subjectName: string; value: string | number }>) {
  return rows
    .map((row) => ({ ...row, value: String(row.value), numericValue: Number(row.value) }))
    .sort((a, b) => b.numericValue - a.numericValue || a.subjectId.localeCompare(b.subjectId))
    .slice(0, 100)
    .map((row, index) => ({ rank: index + 1, subjectId: row.subjectId, subjectName: row.subjectName, value: row.value }));
}

export function isRankingMetric(value: string | undefined): value is RankingMetric {
  return value != null && (RANKING_METRICS as readonly string[]).includes(value);
}
