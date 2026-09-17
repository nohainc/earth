import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
const referenceData = fs.readFileSync('db/baseline/03_reference_data.sql', 'utf8');
const functions = fs.readFileSync('db/baseline/02_functions.sql', 'utf8');

test('tax governance defines scopes, constitutional caps, and explicit bases', () => {
  assert.match(schema, /CREATE TABLE tax_governance_rules/);
  assert.match(schema, /maximum_rate_bps/);
  assert.match(schema, /allowed_tax_base_definitions/);
  for (const scope of ['EARTH', 'CORPORATION']) assert.match(schema, new RegExp(`'${scope}'`));
  for (const base of ['fixed_daily_obligation', 'positive_realized_daily_income', 'positive_realized_daily_taxable_profit', 'external_market_trade']) assert.match(referenceData, new RegExp(base));
});

test('tax rule changes require passed proposals and future effective days', () => {
  assert.match(schema, /authorization_proposal_id/);
  assert.match(schema, /effective_to_game_day/);
  assert.match(fs.readFileSync('db/baseline/04_initial_world.sql', 'utf8'), /effective_from_game_day/);
});

test('tax rule lineage serializes concurrent amendments and closes intervals', () => {
  const executor = fs.readFileSync(new URL('../cloudflare/src/proposal-finance-actions.ts', import.meta.url), 'utf8');
  assert.match(schema, /UNIQUE \(tax_rule_id, version\)/);
  assert.match(functions, /earth_create_tax_rule_version/);
  assert.match(functions, /pg_advisory_xact_lock/);
  assert.match(functions, /effective_to_game_day = p_effective_from_game_day - 1/);
  assert.match(functions, /MAX\(version\)/);
  assert.match(executor, /current\.id !== baseVersionId/);
  assert.match(executor, /ORDER BY version DESC/);
  assert.match(executor, /FOR UPDATE/);
});

test('Proposal V2 exposes typed tax amendment actions', () => {
  const actions = fs.readFileSync('cloudflare/src/proposal-actions.ts', 'utf8');
  const finance = fs.readFileSync('cloudflare/src/proposal-finance-actions.ts', 'utf8');
  for (const action of ['AMEND_TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX']) {
    assert.match(actions, new RegExp(action));
    assert.match(finance, new RegExp(action));
  }
  assert.match(finance, /STALE_CONFLICT/);
  assert.match(finance, /Legacy tax rule execution is retired/);
  assert.doesNotMatch(finance, /earth_create_tax_rule_version/);
});
