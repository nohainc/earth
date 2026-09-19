import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const helper = fs.readFileSync('cloudflare/src/house-finance-overview-postgres.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/finance-routes.ts', 'utf8');
const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_personal_finance.dart', 'utf8');
const panel = fs.readFileSync('flutter_client/lib/features/finance/personal_finance_panel.dart', 'utf8');
const registry = fs.readFileSync('cloudflare/src/api-registry.ts', 'utf8');

test('HouseFinanceOverview has one canonical server-owned contract', () => {
  for (const field of [
    'clock', 'wallet', 'liquidity', 'obligations', 'capacity', 'bank', 'tax', 'cashflow',
  ]) assert.match(helper, new RegExp(`\\b${field}\\b`));
  assert.match(helper, /contractVersion: 'v5-house-finance-overview-1'/);
  assert.match(helper, /balanceUnits: walletUnits\.toString\(\)/);
  assert.match(helper, /nextSettlement/);
  assert.match(helper, /recentTransactions: transactions\.rows/);
  assert.match(helper, /loanSchedules/);
  assert.match(helper, /otherObligations/);
  assert.match(helper, /normalizeObligationStatus/);
  assert.match(helper, /totalRemainingUnits/);
  assert.match(helper, /capacity-resolution/);
  assert.doesNotMatch(helper, /protectedReserveUnits|protected_credits|unpaidDailyNeedUnits/);
  assert.doesNotMatch(routes, /businesses: \[\]|protectedMinimum|protectedReserveUnits|unpaidTotal/);
});

test('Finance routes expose the canonical overview and deprecate split reads', () => {
  assert.match(routes, /url\.pathname === '\/api\/finance\/overview'/);
  assert.match(routes, /url\.pathname === '\/api\/finance\/me'/);
  assert.match(routes, /url\.pathname === '\/api\/finance\/personal'/);
  assert.match(routes, /headers\.set\('Deprecation', 'true'\)/);
  assert.match(registry, /'\/api\/finance\/overview'.*status: 'ACTIVE'/);
  assert.match(registry, /'\/api\/finance\/me'.*status: 'DEPRECATED'/);
  assert.match(registry, /'\/api\/finance\/personal'.*status: 'DEPRECATED'/);
});

test('Flutter requests and consumes the canonical model', () => {
  assert.match(api, /_request\('\/api\/finance\/overview'\)/);
  assert.match(panel, /HouseFinanceOverview\.fromJson/);
  assert.match(panel, /finance\.obligations/);
  assert.match(panel, /finance\.cashflow/);
  assert.match(panel, /NEXT SETTLEMENT FORECAST/);
  assert.match(panel, /HISTORICAL CASHFLOW/);
  assert.match(panel, /finance\.cashflow\.recentTransactions/);
  assert.match(panel, /OBLIGATIONS/);
  assert.match(panel, /CAPACITY OBLIGATION/);
  assert.match(panel, /OPEN RESOLUTION/);
  assert.match(api, /openCapacityResolution/);
});
