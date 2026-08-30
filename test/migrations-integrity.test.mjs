import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('database migrations: verify the consolidated baseline and active migration sequence', () => {
  const migrationsDir = path.resolve('db/migrations');
  const manifestPath = path.resolve('db/schema-manifest.json');
  const initialPath = path.resolve('db/initial.sql');

  const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  assert.ok(files.length >= 1, 'Expected forward-only migrations after the baseline');
  assert.equal(files[0], '075_daily_settlement_profiles.sql');
  assert.ok(!files.some((file) => Number(file.slice(0, 3)) <= 74), 'Migrations 001-074 must be consolidated into db/initial.sql');

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.migrationVersion, Number(files.at(-1).slice(0, 3)), 'Manifest version must match latest migration version');

  const initial = fs.readFileSync(initialPath, 'utf8');
  assert.ok(!initial.includes('\\ir '), 'Initial baseline must be self-contained');
  assert.ok(initial.includes('(74,'), 'Initial baseline must mark migration 074 as applied');
  assert.ok(manifest.requiredTables.building_settlement_journals, 'Manifest must contain building_settlement_journals');
});
