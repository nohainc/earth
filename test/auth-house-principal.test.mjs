import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('authentication is House-scoped and current Human is resolved per request', () => {
  const migration = read('db/migrations/294_house_authentication_principal.sql');
  const session = read('cloudflare/src/auth-session.ts');
  const auth = read('cloudflare/src/auth-postgres.ts');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS auth_accounts/);
  assert.match(migration, /house_id TEXT NOT NULL REFERENCES houses/);
  assert.match(migration, /auth_sessions[\s\S]*account_id/);
  assert.match(migration, /auth_action_tokens[\s\S]*account_id/);
  assert.match(session, /JOIN auth_accounts ON auth_accounts\.id = auth_sessions\.account_id/);
  assert.match(session, /JOIN humans ON humans\.id = houses\.current_human_id/);
  assert.doesNotMatch(session, /JOIN auth_credentials ON auth_credentials\.human_id/);
  assert.match(auth, /FROM auth_accounts/);
  assert.match(auth, /INSERT INTO auth_sessions \(id,account_id,human_id/);
  assert.doesNotMatch(lifecycle, /UPDATE auth_sessions SET revoked_at/);
  assert.doesNotMatch(migration, /UPDATE auth_sessions SET revoked_at/);
});
