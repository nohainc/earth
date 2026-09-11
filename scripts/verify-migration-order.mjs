import { readdir, readFile } from 'node:fs/promises';

const names = (await readdir(new URL('../db/migrations/', import.meta.url)))
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort((a, b) => Number(a.match(/^\d+/)[0]) - Number(b.match(/^\d+/)[0]));
const versions = names.map((name) => Number(name.match(/^\d+/)[0]));
const failures = [];
for (let index = 1; index < versions.length; index += 1) {
  if (versions[index] === versions[index - 1]) failures.push(`duplicate migration version ${versions[index]}`);
  if (versions[index] < versions[index - 1]) failures.push(`migration order is not numeric at ${names[index - 1]} / ${names[index]}`);
}
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url)));
const schema = await readFile(new URL('../db/schema.sql', import.meta.url), 'utf8');
const latest = versions.at(-1) ?? 0;
if (manifest.migrationVersion !== latest) failures.push(`manifest head ${manifest.migrationVersion} != migration head ${latest}`);
if (!schema.includes(`reconciled through migration ${manifest.migrationVersion}`)) failures.push('canonical schema header does not match manifest head');
if (failures.length) throw new Error(`Migration audit failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, migrationCount: names.length, migrationVersion: latest }));
