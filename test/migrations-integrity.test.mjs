import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('database migrations: verify sequential migration files, schema.sql, functions.sql, and schema manifest version', () => {
  const migrationsDir = path.resolve('db/migrations');
  const manifestPath = path.resolve('db/schema-manifest.json');
  const schemaPath = path.resolve('db/schema.sql');
  const functionsPath = path.resolve('db/functions.sql');

  const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  assert.ok(files.length >= 83, `Expected at least 83 migrations, found ${files.length}`);
  assert.equal(files[0], '001_initial.sql');
  assert.equal(files.at(-1), '121_remove_human_supply_contracts.sql');

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.migrationVersion, 121, 'Manifest version must match latest migration version (121)');

  const schema = fs.readFileSync(schemaPath, 'utf8');
  assert.ok(schema.includes('CREATE TABLE IF NOT EXISTS buildings'), 'Canonical schema.sql must define buildings');
  assert.ok(schema.includes('CREATE TABLE IF NOT EXISTS houses'), 'Canonical schema.sql must define houses');
  assert.ok(!schema.includes('character_lineage'), 'Canonical schema.sql must not include dropped character_lineage');
  assert.ok(!schema.includes('asset_ownership_events'), 'Canonical schema.sql must not include dropped asset_ownership_events');
  assert.ok(manifest.requiredTables.building_settlement_journals, 'Manifest must contain building_settlement_journals');
  assert.ok(manifest.requiredTables.human_technology_subscriptions, 'Manifest must contain human technology subscriptions');
  assert.ok(!manifest.requiredTables.businesses, 'Manifest must not contain the removed Business table');

  const functions = fs.readFileSync(functionsPath, 'utf8');
  assert.ok(functions.includes('CREATE OR REPLACE FUNCTION earth_transfer_credits'), 'functions.sql must contain earth_transfer_credits');
});
