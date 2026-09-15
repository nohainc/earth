import test from 'node:test';
import assert from 'node:assert/strict';
import { RANKING_METRICS, RANKING_RULES_VERSION, rankMetricRows } from '../cloudflare/src/rankings.ts';

test('V4 rankings expose independent dimensions without a composite score', () => {
  assert.ok(RANKING_METRICS.length >= 5);
  assert.equal(RANKING_RULES_VERSION, 'rankings-v1');
  assert.deepEqual(rankMetricRows([
    { subjectId: 'B', subjectName: 'Beta', value: '4' },
    { subjectId: 'A', subjectName: 'Alpha', value: '4' },
    { subjectId: 'C', subjectName: 'Gamma', value: '9' },
  ]).map((row) => row.subjectId), ['C', 'A', 'B']);
});
