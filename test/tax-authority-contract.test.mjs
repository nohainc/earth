import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('V4 tax statements expose explicit public authority and nexus traceability', () => {
  const migration = fs.readFileSync('db/migrations/053_tax_authority_and_statement_traceability.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/tax-statement-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/finance-routes.ts', 'utf8');
  const settlement = fs.readFileSync('cloudflare/src/tax-settlement-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS tax_authorities/);
  assert.match(migration, /TERRITORY_GOVERNANCE/);
  assert.match(migration, /authority_type/);
  assert.match(migration, /base_reference/);
  assert.match(service, /house_residencies/);
  assert.match(service, /authority_type/);
  assert.match(service, /nexus_type/);
  assert.match(service, /financial_obligations/);
  assert.match(service, /tax_obligations/);
  assert.match(routes, /tax-statement/);
  assert.match(settlement, /financial_obligations/);
  assert.match(settlement, /earth_post_transaction/);
  assert.match(settlement, /status = 'ARREARS'/);
  assert.match(settlement, /assessedDay = day - 1/);
  assert.match(scheduler, /settlePublicTaxesInTransaction/);
});

test('ordinary Organization membership is not accepted as tax authority', () => {
  const service = fs.readFileSync('cloudflare/src/tax-statement-postgres.ts', 'utf8');
  assert.doesNotMatch(service, /organization_memberships.*tax/i);
  assert.match(service, /authority_type/);
  assert.match(service, /getResolvedConstitutionForDay/);
  assert.doesNotMatch(service, /TERRITORY_GOVERNANCE/);
});
