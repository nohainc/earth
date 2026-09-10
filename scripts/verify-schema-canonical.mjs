import { readFile } from 'node:fs/promises';

const schema = await readFile(new URL('../db/schema.sql', import.meta.url), 'utf8');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const failures = [];

for (const [table, columns] of Object.entries(manifest.requiredTables)) {
  const definition = schema.match(new RegExp(`CREATE\\s+(?:UNLOGGED\\s+)?TABLE(?:\\s+IF\\s+NOT\\s+EXISTS)?\\s+${table}\\s*\\(([\\s\\S]*?)\\n\\);`, 'i'))?.[1];
  if (!definition) {
    failures.push(`schema.sql is missing table ${table}`);
    continue;
  }
  for (const column of [...new Set(columns)]) {
    const definedInTable = new RegExp(`(?:^|[,\\n]\\s*)${column}\\s+`, 'im').test(definition);
    const definedByReconciliation = new RegExp(`ALTER\\s+TABLE\\s+${table}\\s+ADD\\s+COLUMN(?:\\s+IF\\s+NOT\\s+EXISTS)?\\s+${column}\\s+`, 'i').test(schema);
    if (!definedInTable && !definedByReconciliation) {
      failures.push(`schema.sql table ${table} is missing column ${column}`);
    }
  }
}

if (!schema.includes('reconciled through migration 181')) failures.push('schema.sql header must identify migration 181 reconciliation');
if (failures.length) throw new Error(`Canonical schema verification failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, migrationVersion: manifest.migrationVersion, tablesChecked: Object.keys(manifest.requiredTables).length }, null, 2));
