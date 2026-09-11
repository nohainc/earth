import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/336_institution_financial_events.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const spending = fs.readFileSync(new URL('../cloudflare/src/institution-spending.ts', import.meta.url), 'utf8');
const grants = fs.readFileSync(new URL('../cloudflare/src/institution-grants.ts', import.meta.url), 'utf8');
const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');

test('institution financial events are a linked narrative, not a second ledger', () => {
  for (const source of [migration, schema]) {
    assert.match(source, /institution_financial_events/);
    assert.match(source, /economic_transaction_id/);
    assert.match(source, /correlation_id/);
    assert.match(source, /earth_record_institution_financial_event/);
  }
  assert.match(spending, /earth_record_institution_financial_event/);
  assert.match(grants, /GRANT_SENT/);
  assert.match(grants, /GRANT_RECEIVED/);
  assert.match(scheduler, /RECEIVERSHIP_STARTED/);
  assert.match(scheduler, /LIQUIDATION_STARTED/);
});
