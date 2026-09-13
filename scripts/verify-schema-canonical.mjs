import { readFile, readdir } from 'node:fs/promises';

const schema = await readFile(new URL('../db/baseline/01_schema.sql', import.meta.url), 'utf8');
const baseline = await readFile(new URL('../db/migrations/001_baseline.sql', import.meta.url), 'utf8');
const migrationDirectory = new URL('../db/migrations/', import.meta.url);
const forwardMigrations = (await readdir(migrationDirectory))
  .filter((file) => /^\d+_.+\.sql$/.test(file) && file !== '001_baseline.sql')
  .map((file) => readFile(new URL(file, migrationDirectory), 'utf8'));
const appliedSources = `${schema}\n${(await Promise.all(forwardMigrations)).join('\n')}`;
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const failures = [];

for (const [table, columns] of Object.entries(manifest.requiredTables)) {
  if (table === 'earth_schema_migrations') continue;
    const definition = appliedSources.match(new RegExp(`CREATE\\s+(?:UNLOGGED\\s+)?TABLE(?:\\s+IF\\s+NOT\\s+EXISTS)?\\s+${table}\\s*\\(([\\s\\S]*?)\\)\\s*;`, 'i'))?.[1];
  if (!definition) {
    failures.push(`schema.sql is missing table ${table}`);
    continue;
  }
  for (const column of [...new Set(columns)]) {
    const definedInTable = new RegExp(`(?:^|[,\\n]\\s*)${column}\\s+`, 'im').test(definition);
    const definedByReconciliation = new RegExp(`(?:CREATE\\s+TABLE(?:\\s+IF\\s+NOT\\s+EXISTS)?\\s+${table}\\s*\\([\\s\\S]*?\\b${column}\\s+|ALTER\\s+TABLE\\s+${table}\\s+ADD\\s+COLUMN(?:\\s+IF\\s+NOT\\s+EXISTS)?\\s+${column}\\s+)`, 'i').test(appliedSources);
    if (!definedInTable && !definedByReconciliation) {
      failures.push(`schema.sql table ${table} is missing column ${column}`);
    }
  }
}

if (!baseline.includes('-- EARTH ACTIVE MIGRATION: clean baseline')) failures.push('baseline migration marker is missing');
if (manifest.migrationVersion < 1) failures.push(`baseline manifest must have a valid version, found ${manifest.migrationVersion}`);
if (failures.length) throw new Error(`Canonical schema verification failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, migrationVersion: manifest.migrationVersion, tablesChecked: Object.keys(manifest.requiredTables).length }, null, 2));
