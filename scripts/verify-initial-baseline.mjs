import { readdir, readFile } from 'node:fs/promises';

const schema = await readFile(new URL('../db/schema.sql', import.meta.url), 'utf8');
const functions = await readFile(new URL('../db/functions.sql', import.meta.url), 'utf8');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const migrationsDirectory = new URL('../db/migrations/', import.meta.url);
const migrationNames = (await readdir(migrationsDirectory))
  .filter((name) => /^\d{3}_.+\.sql$/.test(name))
  .sort();
const latestMigrationVersion = Number(migrationNames.at(-1)?.slice(0, 3) ?? 0);

const failures = [];
if (!schema.includes('CREATE TABLE IF NOT EXISTS buildings')) failures.push('db/schema.sql must contain canonical schema definitions');
if (!functions.includes('CREATE OR REPLACE FUNCTION earth_transfer_credits')) failures.push('db/functions.sql must contain earth_transfer_credits');
if (schema.includes('character_lineage')) failures.push('db/schema.sql must not include dropped character_lineage');
if (schema.includes('asset_ownership_events')) failures.push('db/schema.sql must not include dropped asset_ownership_events');
if (latestMigrationVersion < manifest.migrationVersion) failures.push(`expected migration version ${manifest.migrationVersion} or newer, found ${latestMigrationVersion}`);

if (failures.length) throw new Error(`Schema verification failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, totalMigrations: migrationNames.length, manifestVersion: manifest.migrationVersion, latestMigration: migrationNames.at(-1) }, null, 2));
