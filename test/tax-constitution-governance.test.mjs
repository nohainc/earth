import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/348_tax_constitution_governance.sql', 'utf8');

test('tax governance defines scopes, constitutional caps, and explicit bases', () => {
  assert.match(migration, /tax_governance_rules/);
  assert.match(migration, /maximum_rate_bps/);
  assert.match(migration, /allowed_tax_base_definitions/);
  for (const scope of ['OUC', 'CITY', 'CORPORATION']) assert.match(migration, new RegExp(`'${scope}'`));
  for (const base of ['fixed_daily_obligation', 'positive_realized_daily_income', 'positive_realized_daily_taxable_profit', 'external_market_trade']) assert.match(migration, new RegExp(base));
});

test('tax rule changes require passed proposals and future effective days', () => {
  assert.match(migration, /decision_status = 'passed'/);
  assert.match(migration, /authorization_proposal_id/);
  assert.match(migration, /cannot be retroactive or overlap/);
  assert.match(migration, /tax_rule_versions_governance_trigger/);
});

test('Proposal V2 exposes typed tax amendment actions', () => {
  const actions = fs.readFileSync('cloudflare/src/proposal-actions.ts', 'utf8');
  const finance = fs.readFileSync('cloudflare/src/proposal-finance-actions.ts', 'utf8');
  for (const action of ['AMEND_TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX']) {
    assert.match(actions, new RegExp(action));
    assert.match(finance, new RegExp(action));
  }
  assert.match(finance, /STALE_CONFLICT/);
  assert.match(finance, /earth_create_tax_rule_version/);
});
