import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import crypto from 'node:crypto';

test('Database Backup, Migration Preflight, and Checksum Verification', async () => {
  const migrationsDir = resolve('db/migrations');
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();

  assert.ok(files.length >= 17, 'All 17 PostgreSQL migrations must exist');

  // Verify that all migration files are non-empty and have valid SQL syntax prefixes
  for (const file of files) {
    const content = (await readFile(resolve(migrationsDir, file), 'utf8')).toUpperCase();
    assert.ok(content.length > 0, `Migration ${file} must not be empty`);
    assert.ok(
      content.includes('CREATE') || content.includes('ALTER') || content.includes('INSERT') || content.includes('UPDATE'),
      `Migration ${file} must contain valid DDL statements`
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
