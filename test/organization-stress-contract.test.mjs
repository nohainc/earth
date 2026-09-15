import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { evaluateOrganizationHealth } from '../cloudflare/src/organization-stress.ts';

test('organization health transitions are deterministic and non-destructive', () => {
  assert.equal(evaluateOrganizationHealth({ assetsUnits: 100n, liabilitiesUnits: 100n, liquidUnits: 100n, overdueUnits: 0n }), 'HEALTHY');
  assert.equal(evaluateOrganizationHealth({ assetsUnits: 100n, liabilitiesUnits: 100n, liquidUnits: 60n, overdueUnits: 0n }), 'WATCH');
  assert.equal(evaluateOrganizationHealth({ assetsUnits: 100n, liabilitiesUnits: 100n, liquidUnits: 10n, overdueUnits: 10n }), 'STRESS');
  assert.equal(evaluateOrganizationHealth({ assetsUnits: 0n, liabilitiesUnits: 100n, liquidUnits: 0n, overdueUnits: 100n }), 'INSOLVENT');
});

test('organization resolution schema preserves cases, claims, and successor mappings', () => {
  const migration = fs.readFileSync('db/migrations/045_organization_stress_resolution.sql', 'utf8');
  for (const table of ['organization_financial_states', 'organization_resolution_cases', 'organization_creditor_claims', 'organization_successor_mappings']) assert.match(migration, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`));
  assert.doesNotMatch(migration, /ON DELETE CASCADE/i);
});

test('organization risk has a canonical member-facing API and settlement handler', () => {
  const routes = fs.readFileSync('cloudflare/src/api-registry.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  assert.match(routes, /GET.*\/api\/finance\/organizations\/\{id\}\/risk/);
  assert.match(scheduler, /refreshOrganizationFinancialStates/);
  assert.match(routes, /POST.*\/api\/finance\/organizations\/\{id\}\/resolution/);
  assert.match(fs.readFileSync('cloudflare/src/organization-stress-postgres.ts', 'utf8'), /approved_proposal_id/);
  const executor = fs.readFileSync('cloudflare/src/organization-stress-postgres.ts', 'utf8');
  assert.match(executor, /organization_successor_mappings/);
  assert.match(executor, /UPDATE buildings SET owner_economic_id/);
  assert.match(executor, /LIMIT 100 FOR UPDATE SKIP LOCKED/);
});
