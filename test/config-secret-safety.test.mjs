import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { authorityMode } from '../cloudflare/src/repository.ts';

test('Configuration, Persistence Authority, and Secret Safety Validation', async () => {
  // 1. Authority validation: requires PERSISTENCE_AUTHORITY='postgres'
  assert.throws(
    () => authorityMode({ PERSISTENCE_AUTHORITY: 'd1' }),
    /PostgreSQL persistence authority is required/
  );
  assert.throws(
    () => authorityMode({ PERSISTENCE_AUTHORITY: 'memory' }),
    /PostgreSQL persistence authority is required/
  );
  assert.equal(authorityMode({ PERSISTENCE_AUTHORITY: 'postgres' }), 'postgres');

  // 2. Wrangler Configuration & Binding Validation
  const wranglerRaw = await readFile(resolve('wrangler.jsonc'), 'utf8');
  assert.ok(wranglerRaw.includes('HYPERDRIVE'), 'wrangler.jsonc must configure HYPERDRIVE binding');
  assert.ok(wranglerRaw.includes('MARKET_COORDINATOR'), 'wrangler.jsonc must configure MARKET_COORDINATOR Durable Object');
  assert.ok(wranglerRaw.includes('EMAIL'), 'wrangler.jsonc must configure EMAIL binding');
  assert.ok(wranglerRaw.includes('auth.earthuc.com'), 'Email domain must match approved sender');

  // 3. Verify no secrets or credentials appear in wrangler.jsonc or public code
  assert.equal(wranglerRaw.includes('postgres://'), false, 'wrangler.jsonc must never contain hardcoded database URIs');
  assert.equal(wranglerRaw.includes('password='), false, 'wrangler.jsonc must never contain raw passwords');
});
