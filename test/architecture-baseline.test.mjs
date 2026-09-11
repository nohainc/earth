import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('architecture baseline matches the current migration and schema heads', () => {
  const migrationsDir = path.resolve('db/migrations');
  const migrations = fs.readdirSync(migrationsDir).filter((file) => file.endsWith('.sql')).sort();
  const latest = migrations.at(-1);
  const version = Number(latest?.match(/^(\d+)_/)?.[1]);
  const baseline = fs.readFileSync(path.resolve('docs/ARCHITECTURE_BASELINE.md'), 'utf8');
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));

  assert.equal(latest, '341_human_daily_needs_v2.sql');
  assert.equal(version, 341);
  assert.match(baseline, /Migration head: `341_human_daily_needs_v2\.sql`/);
  assert.match(baseline, /Canonical fresh-install schema: `db\/schema\.sql`, reconciled through migration\s+341/);
  assert.match(schema, /reconciled through migration 341/);
  assert.equal(manifest.migrationVersion, 341);
});

test('architecture baseline names the V2 authorities and known transitional paths', () => {
  const baseline = fs.readFileSync(path.resolve('docs/ARCHITECTURE_BASELINE.md'), 'utf8');
  for (const authority of ['House', 'Human', 'Economy V2', 'Building V2', 'Market V2', 'Finance V2', 'Technology/IP V2', 'Budgets V2', 'Scheduler V2']) {
    assert.match(baseline, new RegExp(`\\| ${authority.replace('/', '\\/')} \\|`));
  }
  for (const legacy of ['account_balances', 'resource_balances', 'earth_catchup_owner_settlement', 'transferCredits', 'EARTH_SCHEDULER_MAX_CATCHUP_DAYS']) {
    assert.match(baseline, new RegExp(legacy.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
});
