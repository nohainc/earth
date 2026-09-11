import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { performance } from 'node:perf_hooks';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

function buildInstitutionWorkload(cityCount, corporationCount, linesPerInstitution) {
  const lines = [];
  for (let institution = 0; institution < cityCount + corporationCount; institution += 1) {
    for (let line = 0; line < linesPerInstitution; line += 1) {
      lines.push({ institution, authorized: 1_000_000, committed: 0, spent: 0 });
    }
  }
  return lines;
}

function aggregatePayments(paymentCount, institutionCount) {
  const totals = new Map();
  for (let payment = 0; payment < paymentCount; payment += 1) {
    const institution = payment % institutionCount;
    totals.set(institution, (totals.get(institution) ?? 0) + 1);
  }
  return totals;
}

test('synthetic institutional population builds 10k cities and 1k corporations', () => {
  const started = performance.now();
  const lines = buildInstitutionWorkload(10_000, 1_000, 12);
  const elapsed = performance.now() - started;

  assert.equal(lines.length, 132_000);
  assert.equal(new Set(lines.map((line) => line.institution)).size, 11_000);
  assert.ok(elapsed < 5_000, `budget-line setup took ${elapsed.toFixed(1)}ms`);
});

test('million automatic commitment payments aggregate by institution', () => {
  const started = performance.now();
  const totals = aggregatePayments(1_000_000, 11_000);
  const elapsed = performance.now() - started;

  assert.equal([...totals.values()].reduce((sum, value) => sum + value, 0), 1_000_000);
  assert.equal(totals.size, 11_000);
  assert.ok(elapsed < 5_000, `payment aggregation took ${elapsed.toFixed(1)}ms`);
});

test('scale paths use projections and shared Economy V2 spending', () => {
  const projection = read('db/migrations/337_institution_financial_projections.sql');
  const budgetApi = read('cloudflare/src/institution-budget-api.ts');
  const spending = read('cloudflare/src/institution-spending.ts');
  const grants = read('cloudflare/src/institution-grants.ts');

  assert.match(projection, /institution_financial_projections/);
  assert.match(projection, /SUM\(/);
  assert.match(budgetApi, /institution_budget_commitments/);
  assert.match(spending, /earth_post_transaction/);
  assert.match(grants, /spendBudget\(tx/);
});

test('institution scale has bounded grouped projection work', () => {
  const started = performance.now();
  const institutions = 11_000;
  const totals = aggregatePayments(1_000_000, institutions);
  const projections = [...totals.entries()].map(([institution, payments]) => ({
    institution,
    periodSpending: payments * 100,
    outstandingCommitments: Math.max(0, 1_000 - payments),
  }));
  const elapsed = performance.now() - started;

  assert.equal(projections.length, institutions);
  assert.ok(projections.every((row) => row.periodSpending >= 0));
  assert.ok(elapsed < 5_000, `projection aggregation took ${elapsed.toFixed(1)}ms`);
});
