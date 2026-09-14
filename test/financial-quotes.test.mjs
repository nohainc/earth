import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/financial-quotes.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/finance-routes.ts', 'utf8');

test('server quote contract covers all financial operation types', () => {
  for (const kind of ['CONSTRUCTION', 'UPGRADE', 'RETROFIT', 'OVERHAUL', 'RESEARCH', 'TECHNOLOGY_ADOPTION', 'LICENSING', 'PUBLIC_PROJECT']) assert.match(source, new RegExp(kind));
  for (const field of ['baseAmount', 'fees', 'taxes', 'total', 'payer', 'recipientTreatment', 'ruleVersion', 'definitionVersion']) assert.match(source, new RegExp(field));
});

test('quote API is server-owned and does not accept client amounts', () => {
  assert.match(routes, /getFinancialQuote/);
  assert.match(routes, /\/api\/finance\/quote/);
  assert.doesNotMatch(routes, /amount.*searchParams/);
});
