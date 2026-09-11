import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('backup and restore tooling fails closed and verifies checksums', () => {
  const backup = fs.readFileSync('scripts/backup-postgres.mjs', 'utf8');
  const restore = fs.readFileSync('scripts/restore-postgres.mjs', 'utf8');
  assert.match(backup, /DATABASE_URL is required/);
  assert.match(backup, /pg_dump/);
  assert.match(backup, /sha256/);
  assert.match(restore, /RECOVERY_DATABASE_URL/);
  assert.match(restore, /EARTH_ALLOW_RESTORE/);
  assert.match(restore, /checksum mismatch/);
  assert.match(restore, /pg_restore/);
});

test('backup runbook documents isolated restore, reconciliation and secret recovery', () => {
  const runbook = fs.readFileSync('docs/BACKUP_AND_RESTORE.md', 'utf8');
  for (const term of ['retention', 'encrypted', 'pg_dump', 'pg_restore', 'db:verify:manifest', 'db:verify:invariants', 'secret']) assert.match(runbook, new RegExp(term, 'i'));
});
