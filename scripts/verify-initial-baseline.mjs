import { readdir, readFile } from 'node:fs/promises';

const baselineVersion = 74;
const initial = await readFile(new URL('../db/initial.sql', import.meta.url), 'utf8');
const migrationsDirectory = new URL('../db/migrations/', import.meta.url);
const migrationNames = (await readdir(migrationsDirectory))
  .filter((name) => /^\d{3}_.+\.sql$/.test(name))
  .sort();

const failures = [];
if (initial.includes('\\ir ')) failures.push('db/initial.sql must not include other migration files');
if (!initial.includes(`bootstrap baseline through migration ${baselineVersion}`)) failures.push(`baseline must identify migration ${baselineVersion}`);
for (let version = 1; version <= baselineVersion; version += 1) {
  if (!initial.includes(`  (${version}, '`)) failures.push(`baseline migration ledger is missing version ${version}`);
}
if (migrationNames.some((name) => Number(name.slice(0, 3)) <= baselineVersion)) {
  failures.push(`migrations 001-${baselineVersion} must be consolidated into db/initial.sql, not kept as active files`);
}
if (migrationNames.length && Number(migrationNames[0].slice(0, 3)) !== baselineVersion + 1) {
  failures.push(`the first active migration must be ${String(baselineVersion + 1).padStart(3, '0')}`);
}

if (failures.length) throw new Error(`Initial PostgreSQL baseline failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, baselineVersion, activeMigrations: migrationNames.length }, null, 2));
