import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/223_institution_bailouts_v2.sql', import.meta.url), 'utf8');
const finance = fs.readFileSync(new URL('../cloudflare/src/finance-postgres.ts', import.meta.url), 'utf8');

test('institution recovery distinguishes fiscal redistribution from monetary issuance', () => {
  assert.match(migration, /institution_bailouts/);
  assert.match(migration, /bailout_kind IN \('FISCAL', 'MONETARY'\)/);
  assert.match(migration, /earth_post_fiscal_bailout/);
  assert.match(migration, /earth_post_monetary_emergency_support/);
  assert.match(migration, /earth_post_monetary_operation/);
  assert.match(migration, /governance_authorization/);
  assert.match(migration, /FISCAL_BAILOUT/);
  assert.match(migration, /MONETARY_STABILIZATION/);
  assert.match(finance, /earth_post_fiscal_bailout/);
});
