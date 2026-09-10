import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const sourceRoot = new URL('../cloudflare/src/', import.meta.url);
const legacyObjects = [
  'account_balances', 'resource_balances', 'ledger_entries', 'resource_ledger_entries',
  'earth_catchup_owner_settlement', 'earth_rebuild_settlement_profile',
  'resource_rate_history', 'earth_record_rate_change',
];
const files = [];
async function collect(directory) {
  for (const name of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory.pathname, name.name);
    if (name.isDirectory()) await collect(new URL(`file://${path}/`));
    else if (name.name.endsWith('.ts')) files.push(path);
  }
}
await collect(sourceRoot);

const references = [];
const mutations = [];
for (const file of files) {
  if (file.endsWith('/economy-shadow.ts')) continue;
  const source = await readFile(file, 'utf8');
  for (const object of legacyObjects) {
    const pattern = new RegExp(`(?:INSERT\\s+INTO|UPDATE|DELETE\\s+FROM)\\s+${object}\\b|${object}`, 'gi');
    let match;
    while ((match = pattern.exec(source))) {
      const line = source.slice(0, match.index).split('\n').length;
      const text = source.split('\n')[line - 1]?.trim() ?? '';
      const isMutation = /^(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)/i.test(match[0]);
      (isMutation ? mutations : references).push({ file: file.replace(`${sourceRoot.pathname}`, ''), line, object, mutation: isMutation, text });
    }
  }
}

const result = {
  ready: mutations.length === 0 && references.length === 0,
  productionFilesScanned: files.length,
  legacyReferences: references,
  legacyMutationCallers: mutations,
  nextStep: mutations.length || references.length
    ? 'Migrate every listed production caller, stop dual writes, reconcile legacy data, then rerun with --enforce.'
    : 'Legacy accounting may be archived and removed through a reviewed forward migration.',
};
console.log(JSON.stringify(result, null, 2));
if (process.argv.includes('--enforce') && !result.ready) process.exitCode = 1;
