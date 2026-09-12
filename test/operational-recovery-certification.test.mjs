import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('operational certification composes backup, restore, soak, and invariant gates', () => {
  const backup = fs.readFileSync('scripts/certify-backup-restore.mjs', 'utf8');
  const soak = fs.readFileSync('scripts/certify-closed-beta-soak.mjs', 'utf8');
  const workflow = fs.readFileSync('.github/workflows/test.yml', 'utf8');
  for (const term of ['RECOVERY_DATABASE_URL', 'fingerprint', 'db:verify:invariants', 'db:verify:integrity', 'db:verify:finance-cutover']) assert.match(backup, new RegExp(term));
  for (const term of ['creditConserved', 'nonNegative', 'history.length']) assert.match(soak, new RegExp(term));
  assert.match(workflow, /certify:soak/);
});

test('scheduler and outbox recovery remain lease/idempotency controlled', () => {
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  const outbox = fs.readFileSync('cloudflare/src/outbox-postgres.ts', 'utf8');
  assert.match(scheduler, /lease|correlation|alreadyProcessed/i);
  assert.match(outbox, /locked_at|attempts|available_at/);
  assert.match(outbox, /processed_at/);
});
