import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('Economy V2 cutover has an enforceable production-reference audit', () => {
  const audit = fs.readFileSync(path.resolve('scripts/verify-economy-v2-cutover.mjs'), 'utf8');
  for (const object of ['account_balances', 'resource_balances', 'ledger_entries', 'resource_ledger_entries', 'earth_catchup_owner_settlement', 'earth_rebuild_settlement_profile', 'resource_rate_history', 'earth_record_rate_change']) assert.match(audit, new RegExp(object));
  assert.match(audit, /legacyMutationCallers/);
  assert.match(audit, /--enforce/);
});
