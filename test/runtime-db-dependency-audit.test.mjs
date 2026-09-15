import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);

function audit() {
  const output = execFileSync(process.execPath, ['scripts/audit-runtime-db-dependencies.mjs', '--json'], {
    cwd: root,
    encoding: 'utf8',
  });
  return JSON.parse(output);
}

test('runtime dependency audit recognises objects added by forward migrations', () => {
  const rows = audit().rows;
  for (const name of ['asset_ownership_positions', 'bank_credit_policies']) {
    const row = rows.find((candidate) => candidate.name === name && candidate.kind === 'table');
    assert.ok(row, `expected an audit row for ${name}`);
    assert.equal(row.present, true, `${name} is created by an active forward migration`);
    assert.equal(row.decision, 'KEEP');
  }
});

test('runtime dependency audit still identifies genuinely absent retained objects', () => {
  const rows = audit().rows;
  const missing = rows.find((row) => row.name === 'auth_credentials' && row.kind === 'table');
  assert.ok(missing, 'expected a retained operational reference that has no active schema object');
  assert.equal(missing.present, false);
  assert.equal(missing.decision, 'KEEP + ADD V2 SCHEMA');
});
