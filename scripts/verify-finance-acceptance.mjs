import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../cloudflare/src/', import.meta.url);
const files = [];
async function collect(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory.pathname, entry.name);
    if (entry.isDirectory()) await collect(new URL(`file://${path}/`));
    else if (entry.name.endsWith('.ts')) files.push(path);
  }
}
await collect(root);

const checks = [
  ['legacy_balance_reference', /account_balances|resource_balances/gi],
  ['legacy_ledger_reference', /ledger_entries|resource_ledger_entries/gi],
  ['legacy_transfer_function', /earth_transfer_credits/gi],
  ['scalar_treasury_reference', /\b(cities|corporations)\.treasury\b/gi],
];
const violations = [];
for (const file of files) {
  const source = await readFile(file, 'utf8');
  for (const [check, pattern] of checks) {
    for (const match of source.matchAll(pattern)) violations.push({ check, file: file.replace(root.pathname, ''), line: source.slice(0, match.index).split('\n').length, token: match[0] });
  }
}
const result = {
  ready: violations.length === 0,
  productionFilesScanned: files.length,
  violations,
  requiredNextStep: violations.length ? 'Migrate the listed shared gameplay callers before removing legacy financial schema.' : 'Finance V2 production references are clean; reconcile data before dropping legacy schema.',
};
console.log(JSON.stringify(result, null, 2));
if (process.argv.includes('--enforce') && violations.length) process.exitCode = 1;
