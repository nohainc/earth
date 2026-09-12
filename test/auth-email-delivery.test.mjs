import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('auth email delivery uses a masked, idempotent audit contract', () => {
  const manifest = JSON.parse(fs.readFileSync('db/schema-manifest.json', 'utf8'));
  for (const column of ['correlation_id', 'account_id', 'recipient_masked', 'provider', 'provider_message_id', 'status', 'accepted_at', 'failed_at', 'updated_at']) {
    assert.ok(manifest.requiredTables.auth_email_deliveries.includes(column), `manifest includes ${column}`);
  }
  assert.ok(manifest.requiredIndexes.includes('auth_email_deliveries_correlation_uq'));
  assert.ok(manifest.requiredIndexes.includes('auth_email_deliveries_account_idx'));
  const source = fs.readFileSync('cloudflare/src/auth-session.ts', 'utf8');
  assert.match(source, /function maskEmail/);
  assert.match(source, /recipientMasked/);
  assert.match(source, /return '\*\*\*@\*\*\*'/);
});

test('email delivery distinguishes provider success from audit persistence', () => {
  const source = fs.readFileSync('cloudflare/src/auth-session.ts', 'utf8');
  assert.match(source, /auditPersisted/);
  assert.match(source, /transactional_email_audit_persistence_failed/);
  assert.match(source, /ON CONFLICT \(correlation_id\)/);
  assert.match(source, /status = 'accepted'/);
  assert.match(source, /status = 'failed'/);
  assert.match(source, /transactional_email_token_cleanup_failed/);
  assert.match(source, /Transactional email is not configured/);
  assert.match(source, /RETURNING account_id/);
});

test('email delivery migration reconciles legacy rows before constraints', () => {
  const migration = fs.readFileSync('db/migrations/353_auth_email_delivery_contract.sql', 'utf8');
  assert.match(migration, /ADD COLUMN IF NOT EXISTS correlation_id/);
  assert.match(migration, /legacy-email:/);
  assert.match(migration, /legacy-redacted/);
  assert.match(migration, /DROP COLUMN IF EXISTS recipient_email/);
  assert.match(migration, /ALTER COLUMN correlation_id SET NOT NULL/);
});
