import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../cloudflare/src/', import.meta.url);
const financeFiles = ['financial-postgres.ts', 'finance-postgres.ts', 'finance-routes.ts', 'global-bank-postgres.ts', 'global-bank-settlement-engine.ts', 'civic-dividend-engine.ts'];
const forbidden = /account_balances|resource_balances|ledger_entries|resource_ledger_entries|earth_transfer_credits/gi;
const violations = [];
for (const name of financeFiles) {
  const source = await readFile(join(root.pathname, name), 'utf8');
  for (const match of source.matchAll(forbidden)) violations.push({ file: name, line: source.slice(0, match.index).split('\n').length, token: match[0] });
}
const result = { ready: violations.length === 0, scanned: financeFiles, violations, dependencyCheck: 'Shared scheduler and institution callers are intentionally outside this finance-owned cutover set and must be migrated before dropping legacy schema.' };
console.log(JSON.stringify(result, null, 2));
if (process.argv.includes('--enforce') && violations.length) process.exitCode = 1;
