import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = new URL('../db/baseline/', import.meta.url);
const files = ['01_schema.sql', '02_functions.sql', '03_reference_data.sql', '04_initial_world.sql'];
const sources = Object.fromEntries(files.map((file) => [file, fs.readFileSync(new URL(file, root), 'utf8')]));

test('clean baseline has all dependency-ordered sections', () => {
  for (const file of files) assert.ok(sources[file].length > 0, `${file} must not be empty`);
  const bundle = fs.readFileSync(new URL('001_baseline.sql', root), 'utf8');
  for (const file of files) assert.match(bundle, new RegExp(String.raw`\\ir ${file}`));
});

test('migration directory exposes the immutable baseline followed by contiguous active migrations', () => {
  const migrationDir = new URL('../db/migrations/', import.meta.url);
  const active = fs.readdirSync(migrationDir)
    .filter((file) => /^\d+_.+\.sql$/.test(file))
    .filter((file) => fs.readFileSync(new URL(file, migrationDir), 'utf8').includes('-- EARTH ACTIVE MIGRATION:'));
  assert.equal(active[0], '001_baseline.sql');
  assert.deepEqual(active, ['001_baseline.sql', '002_communities_v2.sql', '003_community_v2_hardening.sql', '004_public_infrastructure_credit.sql', '005_architecture_integrity_report.sql']);
  const migrator = fs.readFileSync(path.resolve(new URL('../scripts/migrate-postgres.mjs', import.meta.url).pathname), 'utf8');
  assert.match(migrator, /activeMigrations/);
  assert.doesNotMatch(migrator, /ALLOW_MIGRATION_REPAIR/);
});

test('baseline excludes removed gameplay and compatibility domains', () => {
  const source = Object.values(sources).join('\n').toLowerCase();
  for (const removed of [
    'account_balances', 'resource_balances', 'ledger_entries',
    'global_bank_deposits', 'global_bank_loans', 'tax_rules',
    'businesses', 'derivative_obligations', 'delivery_future',
    'human_technology_adoptions', 'human_technology_subscriptions',
    'ai assistant', 'repair queue',
  ]) assert.doesNotMatch(source, new RegExp(removed.replaceAll(' ', '\\s+')), removed);
  assert.doesNotMatch(source, /test-|fake|demo|h-0044|house kline/);
});

test('baseline defines the final economic and Spot Market authorities', () => {
  const schema = sources['01_schema.sql'];
  for (const object of [
    'owner_registry', 'economic_accounts', 'economic_transactions', 'economic_entries',
    'building_catalog', 'buildings', 'market_instruments', 'market_orders', 'market_fills',
    'bank_deposits', 'bank_loans', 'tax_rule_versions', 'tax_obligations',
    'institution_budget_lines', 'technology_catalog', 'corporation_research_projects',
  ]) assert.match(schema, new RegExp(`CREATE TABLE ${object}`), object);
  for (const symbol of ['MATERIAL', 'COMPONENTS', 'ENERGY', 'COMPUTE', 'FOOD']) {
    assert.match(sources['04_initial_world.sql'], new RegExp(symbol));
  }
});

test('schema V3 structurally prevents rebuilding the City hierarchy', () => {
  const schema = sources['01_schema.sql'];
  const referenceData = sources['03_reference_data.sql'];
  const initialWorld = sources['04_initial_world.sql'];

  assert.match(schema, /CREATE TABLE territories/);
  assert.match(schema, /territory_id TEXT NOT NULL REFERENCES territories\(id\)/);
  assert.match(schema, /CREATE UNIQUE INDEX house_affiliations_one_active_idx/);
  assert.match(schema, /CREATE UNIQUE INDEX territories_one_active_primary_idx/);
  assert.match(schema, /CHECK \(kind IN \('EARTH','CORPORATION','BANK'\)\)/);
  assert.match(schema, /CHECK \(owner_type IN \('EARTH','CORPORATION','HOUSE','BANK','SYSTEM'\)\)/);
  assert.match(schema, /CHECK \(scope IN \('EARTH','CORPORATION'\)\)/);
  assert.match(schema, /CHECK \(scope IN \('global', 'corporation', 'community', 'direct'\)\)/);

  for (const source of [schema, referenceData, initialWorld]) {
    assert.doesNotMatch(source, /CREATE TABLE cities|\bcity_id\b|\bCITY\b|\bOUC\b/i);
  }
  assert.doesNotMatch(schema, /owner_type IN \([^)]*CITY/i);
  assert.doesNotMatch(schema, /scope IN \([^)]*CITY/i);
});
