import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const forbidden = /\b(?:FROM|JOIN|UPDATE|INTO|DELETE\s+FROM|INSERT\s+INTO)\s+(?:public\.)?(account_balances|resource_balances|ledger_entries|memberships|businesses|business_financials|business_management|business_shares|ownership_events|membership_events)\b/gi;

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(file) : /\.ts$/.test(entry.name) ? [file] : [];
  });
}

test('production SQL does not reference deleted V1 structures', () => {
  const violations = [];
  for (const file of walk(path.join(root, 'cloudflare/src'))) {
    const source = fs.readFileSync(file, 'utf8');
    for (const match of source.matchAll(forbidden)) {
      const line = source.slice(0, match.index).split('\n').length;
      violations.push(`${path.relative(root, file)}:${line}: ${match[0]}`);
    }
  }
  assert.deepEqual(violations, []);
});
