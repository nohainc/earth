import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/226_personal_bankruptcy_v2.sql', import.meta.url), 'utf8');
const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');

test('personal bankruptcy opens an explicit frozen proceeding from V2 metrics', () => {
  assert.match(migration, /insolvency_proceeding/);
  assert.match(migration, /bankruptcy_proceedings/);
  assert.match(migration, /earth_open_personal_bankruptcy/);
  assert.match(migration, /earth_personal_insolvency_metrics/);
  assert.match(migration, /market_orders_reject_frozen_owner/);
  assert.match(migration, /bank_loans_reject_frozen_owner/);
  assert.match(finance, /earth_open_personal_bankruptcy/);
});

test('corporate insolvency has a separate restructuring lifecycle and estate', () => {
  const migration = fs.readFileSync(new URL('../db/migrations/227_corporation_insolvency_v2.sql', import.meta.url), 'utf8');
  const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /corporation_insolvency_proceedings/);
  assert.match(migration, /RESTRUCTURING/);
  assert.match(migration, /corporation_estate_assets/);
  assert.match(migration, /corporation_creditor_claims/);
  assert.match(migration, /earth_open_corporation_insolvency/);
  assert.match(migration, /earth_reject_distressed_corporation_loan/);
  assert.match(finance, /declareCorporationInsolvency/);
});

test('city fiscal failure uses receivership instead of liquidation', () => {
  const migration = fs.readFileSync(new URL('../db/migrations/228_city_fiscal_insolvency_v2.sql', import.meta.url), 'utf8');
  const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');
  const dividends = fs.readFileSync(new URL('../cloudflare/src/civic-dividend-engine.ts', import.meta.url), 'utf8');
  assert.match(migration, /city_fiscal_proceedings/);
  assert.match(migration, /earth_open_city_receivership/);
  assert.match(migration, /earth_reject_receivership_city_loan/);
  assert.match(finance, /declareCityFiscalReceivership/);
  assert.match(finance, /essential_service/);
  assert.match(dividends, /receivership/);
});

test('global bank distress is explicit and does not silently issue deposits', () => {
  const migration = fs.readFileSync(new URL('../db/migrations/229_global_bank_resolution.sql', import.meta.url), 'utf8');
  assert.match(migration, /global_bank_resolution_state/);
  assert.match(migration, /global_bank_resolution_events/);
  assert.match(migration, /earth_evaluate_global_bank_resolution/);
  assert.match(migration, /LIQUIDITY_STRESS/);
  assert.match(migration, /INSOLVENT/);
  assert.match(migration, /earth_reject_loan_when_bank_stressed/);
  assert.doesNotMatch(migration, /MONETARY_ISSUANCE.*\+|deposit.*whole/i);
});

test('deposit protection is capped and represented as a fiscal claim', () => {
  const migration = fs.readFileSync(new URL('../db/migrations/230_deposit_protection_policy.sql', import.meta.url), 'utf8');
  assert.match(migration, /deposit_protection_rules/);
  assert.match(migration, /deposit_protection_limit_units/);
  assert.match(migration, /deposit_protection_claims/);
  assert.match(migration, /LEAST\(d\.deposit_protection_limit_units/);
  assert.match(migration, /earth_prepare_deposit_protection_claims/);
  assert.doesNotMatch(migration, /earth_post_transaction/);
});

test('finance integrity reports monetary, bank, tax, dividend, and bankruptcy invariants', () => {
  const migration = fs.readFileSync(new URL('../db/migrations/232_finance_v2_invariants.sql', import.meta.url), 'utf8');
  for (const check of ['net_issued_credit_balance_mismatch', 'city_treasury_projection_mismatch', 'corporation_treasury_projection_mismatch', 'deposit_liability_mismatch', 'negative_loan_principal', 'matured_deposit_still_active', 'repaid_loan_with_balance', 'bank_equity_mismatch', 'dividend_exceeds_projection', 'paid_tax_without_transaction', 'bankruptcy_distribution_exceeds_estate', 'issuance_missing_authority_metadata']) assert.match(migration, new RegExp(check));
  assert.match(migration, /earth_finance_v2_integrity/);
  assert.match(migration, /earth_integrity_report/);
});
