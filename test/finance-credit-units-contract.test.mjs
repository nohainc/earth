import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const finance = read('flutter_client/lib/features/finance/personal_finance_panel.dart');
const models = read('flutter_client/lib/core/models/house_finance_models.dart');
const api = read('flutter_client/lib/core/api/earth_api_personal_finance.dart');
const routes = read('cloudflare/src/finance-routes.ts');

test('Finance UI keeps authoritative CREDIT values as exact units', () => {
  assert.match(finance, /BigInt\? _creditUnits/);
  assert.match(finance, /formatCreditUnits\(value/);
  assert.doesNotMatch(finance, /asDouble\(/);
  assert.doesNotMatch(finance, /asDoubleOr\(/);
  assert.doesNotMatch(finance, /delta \/ 100/);
  assert.doesNotMatch(finance, /outstanding_principal_units.*\} C/);
  assert.match(finance, /availableToSpendUnits/);
  assert.match(finance, /_signedCreditText\(delta\)/);
});

test('Bank forms send decimal CREDIT and responses retain exact unit fields', () => {
  assert.match(api, /bankLoanQuote\([\s\S]*required String amount/);
  assert.match(api, /repayBankLoan\([\s\S]*String\? amount/);
  assert.match(api, /createBankDeposit\([\s\S]*required String amount/);
  assert.match(routes, /parseCreditAmount\(amount\)/);
  assert.match(routes, /deposit-quote/);
  assert.match(finance, /bankDepositQuote/);
});

test('Canonical Finance models preserve banking units and projection semantics', () => {
  assert.match(models, /class HouseFinanceOverview/);
  assert.match(models, /class HouseLoan/);
  assert.match(models, /class HouseDeposit/);
  assert.match(models, /BigInt outstandingPrincipalUnits/);
  assert.match(models, /BigInt principalUnits/);
  assert.match(models, /class HouseCashflow/);
  assert.match(finance, /_creditDecimal\(amount\)/);
  assert.doesNotMatch(finance, /shortfall.*(loan|debt)/i);
});
