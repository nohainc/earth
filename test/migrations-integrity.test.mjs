import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('database baseline and schema manifest are internally consistent', () => {
  const root = path.resolve('.');
  const migrationDir = path.join(root, 'db/migrations');
  const baselinePath = path.join(root, 'db/baseline/001_baseline.sql');
  const migrationPath = path.join(migrationDir, '001_baseline.sql');
  const manifestPath = path.join(root, 'db/schema-manifest.json');
  const files = fs.readdirSync(migrationDir).filter((file) => /^\d+_.+\.sql$/.test(file)).sort();

  assert.deepEqual(files, ['001_baseline.sql', '002_communities_v2.sql', '003_community_v2_hardening.sql', '004_public_infrastructure_credit.sql', '005_architecture_integrity_report.sql']);
  const baseline = fs.readFileSync(baselinePath, 'utf8');
  const migration = fs.readFileSync(migrationPath, 'utf8');
  assert.match(migration, /-- EARTH ACTIVE MIGRATION: clean baseline/);
  assert.match(migration, /-- GENERATED FILE/);
  assert.match(migration, /SECTION 1: SCHEMA/);
  assert.match(migration, /SECTION 2: FUNCTIONS/);
  assert.match(migration, /SECTION 3: REFERENCE DATA/);
  assert.match(migration, /SECTION 4: INITIAL WORLD/);

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.migrationVersion, 5);
  assert.equal(manifest.baseline, 'db/baseline/001_baseline.sql');
  for (const table of ['owner_registry', 'economic_accounts', 'building_catalog', 'market_instruments', 'tax_rule_versions', 'technology_catalog']) {
    assert.ok(manifest.requiredTables[table], `${table} must be in the manifest`);
  }

  assert.doesNotMatch(baseline, /DELIVERY_FUTURE|derivative_obligations|account_balances|resource_balances/i);
  assert.doesNotMatch(baseline, /CREATE TABLE[^;]+\b(businesses|global_bank_deposits|global_bank_loans)\b/i);
  assert.doesNotMatch(baseline, /output_credits|auto_repair_enabled|wear_points/i);
});
