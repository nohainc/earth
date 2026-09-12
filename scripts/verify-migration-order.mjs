import { readdir, readFile } from 'node:fs/promises';

const migrationDirectory = new URL('../db/migrations/', import.meta.url);
const names = (await readdir(migrationDirectory))
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort((a, b) => Number(a.match(/^\d+/)[0]) - Number(b.match(/^\d+/)[0]));
const activeNames = [];
for (const name of names) if ((await readFile(new URL(name, migrationDirectory), 'utf8')).includes('-- EARTH ACTIVE MIGRATION:')) activeNames.push(name);
const versions = activeNames.map((name) => Number(name.match(/^\d+/)[0]));
const failures = [];
if (activeNames[0] !== '001_baseline.sql') failures.push(`first active migration must be 001_baseline.sql, found ${activeNames[0] || 'none'}`);
for (let index = 1; index < versions.length; index += 1) {
  if (versions[index] === versions[index - 1]) failures.push(`duplicate migration version ${versions[index]}`);
  if (versions[index] !== versions[index - 1] + 1) failures.push(`active migration sequence is not contiguous at ${activeNames[index - 1]} / ${activeNames[index]}`);
}
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url)));
const latest = versions.at(-1) ?? 0;
if (manifest.migrationVersion !== latest) failures.push(`manifest head ${manifest.migrationVersion} != active migration head ${latest}`);
if (manifest.baseline !== 'db/baseline/001_baseline.sql') failures.push('manifest must identify the clean baseline');
if (failures.length) throw new Error(`Migration audit failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, migrationCount: activeNames.length, ignoredHistoricalFiles: names.length - activeNames.length, migrationVersion: latest }));
