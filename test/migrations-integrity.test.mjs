import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('database migrations: verify sequential migration files and schema manifest version', () => {
  const migrationsDir = path.resolve('db/migrations');
  const manifestPath = path.resolve('db/schema-manifest.json');

  const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  assert.ok(files.length >= 56, `Expected at least 56 migrations, found ${files.length}`);

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.migrationVersion, 56, 'Manifest version must match latest migration version');

  // Verify Migration 056 references valid table names
  const migration056 = fs.readFileSync(path.join(migrationsDir, '056_harden_building_accounting_and_settlement_journals.sql'), 'utf8');
  assert.ok(migration056.includes('REFERENCES patents(id)'), 'Foreign key must reference patents(id)');
  assert.ok(migration056.includes('building_settlement_journals'), 'Must define building_settlement_journals');
  assert.ok(manifest.requiredTables.building_settlement_journals, 'Manifest must contain building_settlement_journals');
});
