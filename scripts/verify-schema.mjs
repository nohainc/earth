import { readFile } from 'node:fs/promises';

const schema = await readFile(new URL('../db/baseline/01_schema.sql', import.meta.url), 'utf8');
const functions = await readFile(new URL('../db/baseline/02_functions.sql', import.meta.url), 'utf8');
const baseline = await readFile(new URL('../db/baseline/001_baseline.sql', import.meta.url), 'utf8');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const failures = [];
if (!schema.includes('CREATE TABLE buildings')) failures.push('baseline schema must contain buildings');
if (!functions.includes('CREATE OR REPLACE FUNCTION earth_post_transaction')) failures.push('baseline functions must contain economic posting');
if (!baseline.includes('\\ir 01_schema.sql') || !baseline.includes('\\ir 04_initial_world.sql')) failures.push('baseline migration must include all sections');
if (manifest.migrationVersion !== 1) failures.push(`expected baseline migration version 1, found ${manifest.migrationVersion}`);

if (failures.length) throw new Error(`Schema verification failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, manifestVersion: manifest.migrationVersion, baseline: manifest.baseline }, null, 2));
