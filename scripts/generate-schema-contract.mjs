import { readFile, writeFile } from 'node:fs/promises';

const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const generated = `// Generated from db/schema-manifest.json. Do not edit manually.\nexport const EARTH_SCHEMA_VERSION = ${manifest.migrationVersion};\nexport const REQUIRED_SCHEMA_TABLES = ${JSON.stringify(manifest.requiredTables, null, 2)} as const;\nexport const REQUIRED_UNIQUE_CONSTRAINTS = ${JSON.stringify(manifest.requiredUniqueConstraints, null, 2)} as const;\nexport const REQUIRED_INDEXES = ${JSON.stringify(manifest.requiredIndexes, null, 2)} as const;\nexport const REQUIRED_SCHEMA_FUNCTIONS = ${JSON.stringify(manifest.requiredFunctions ?? [], null, 2)} as const;\n`;
const output = new URL('../cloudflare/src/schema-contract.ts', import.meta.url);
if (process.argv.includes('--check')) {
  const current = await readFile(output, 'utf8').catch(() => '');
  if (current !== generated) throw new Error('cloudflare/src/schema-contract.ts is stale; run npm run db:generate:schema-contract');
} else {
  await writeFile(output, generated);
}
