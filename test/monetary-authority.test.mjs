import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/211_monetary_authority_supply.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

test('monetary authority defines explicit CREDIT authority accounts and supply projection', () => {
  for (const reason of ['GENESIS_ISSUANCE', 'PLAYER_STARTING_GRANT', 'MONETARY_STABILIZATION', 'CREDIT_RETIREMENT']) {
    assert.match(migration, new RegExp(reason));
  }
  assert.match(migration, /SYSTEM-MONETARY-AUTHORITY/);
  assert.match(migration, /SYSTEM-MONETARY-RETIREMENT/);
  assert.match(migration, /earth_post_monetary_operation/);
  assert.match(migration, /earth_refresh_monetary_supply_snapshot/);
  assert.match(migration, /earth_validate_monetary_authority_transaction/);
  assert.match(migration, /source_type <> 'monetary_authority'/);
});

test('canonical schema includes the monetary supply projection and authority owners', () => {
  assert.match(schema, /reconciled through migration 211/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS monetary_supply_snapshots/);
  assert.match(schema, /SYSTEM-MONETARY-AUTHORITY/);
  assert.match(schema, /SYSTEM-MONETARY-RETIREMENT/);
});
