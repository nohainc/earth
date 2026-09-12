import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const report = JSON.parse(execFileSync(process.execPath, ['scripts/audit-db-model.mjs', '--json'], { encoding: 'utf8' }));

test('every current database object has an explicit re-baseline decision', () => {
  const decisions = new Set(['KEEP', 'REDESIGN', 'DELETE']);
  for (const [kind, objects] of Object.entries(report.classified)) {
    assert.ok(Object.keys(objects).length > 0, `${kind} inventory must not be empty`);
    for (const [name, value] of Object.entries(objects)) {
      assert.ok(decisions.has(value), `${kind} ${name} has no valid decision`);
    }
  }
});

test('known removed domains are classified for deletion', () => {
  for (const name of ['account_balances', 'resource_balances', 'ledger_entries', 'global_bank_deposits', 'global_bank_loans', 'tax_rules']) {
    assert.equal(report.classified.tables[name], 'DELETE', name);
  }
});
