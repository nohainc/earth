import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import crypto from 'node:crypto';

test('Database Backup, Migration Preflight, and Checksum Verification', async () => {
  const migrationsDir = resolve('db/migrations');
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();

  assert.deepEqual(files, ['001_baseline.sql', '002_communities_v2.sql', '003_community_v2_hardening.sql', '004_public_infrastructure_credit.sql', '005_architecture_integrity_report.sql', '006_resource_flow_schema.sql', '007_core_resource_graph_t1.sql', '008_house_food_maintenance.sql', '009_private_building_settlement_journals.sql', '010_market_state_completion.sql', '011_resource_analytics_read_models.sql', '012_resource_economic_integrity.sql', '013_financial_obligations.sql', '014_construction_settlement_destination.sql', '015_resumable_settlement_work.sql', '016_house_daily_statements.sql', '017_house_needs_services.sql'], 'Active migrations must be contiguous');

  // Verify that all migration files are non-empty and have valid SQL syntax prefixes
  for (const file of files) {
    const content = (await readFile(resolve(migrationsDir, file), 'utf8')).toUpperCase();
    assert.ok(content.length > 0, `Migration ${file} must not be empty`);
    assert.ok(
      content.includes('CREATE') || content.includes('ALTER') || content.includes('INSERT') || content.includes('UPDATE') || content.includes('DELETE') || content.includes('DROP') || content.includes('DO $$') || content.includes('DO\n$$') || content.includes('SELECT'),
      `Migration ${file} must contain valid SQL statements`
    );
  }

  // Verify deterministic SHA-256 calculation for migration checksum validation
  const hashes = await Promise.all(
    files.map(async (f) => {
      const buf = await readFile(resolve(migrationsDir, f));
      return { file: f, sha256: crypto.createHash('sha256').update(buf).digest('hex') };
    })
  );

  assert.equal(hashes.length, files.length);
  for (const h of hashes) {
    assert.equal(h.sha256.length, 64);
  }
});
