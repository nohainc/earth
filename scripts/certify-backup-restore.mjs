import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { Client } from 'pg';

const run = promisify(execFile);
const source = process.env.DATABASE_URL;
const recovery = process.env.RECOVERY_DATABASE_URL;
const backupDirectory = process.env.EARTH_BACKUP_DIR || 'backups/recovery-certification';
if (!source || !recovery) throw new Error('DATABASE_URL and RECOVERY_DATABASE_URL are required');
if (source === recovery) throw new Error('Recovery target must be different from the source database');
if (process.env.EARTH_ALLOW_RESTORE !== 'true') throw new Error('Set EARTH_ALLOW_RESTORE=true for a dedicated recovery target');

const fingerprintTables = ['world_state', 'houses', 'humans', 'economic_accounts', 'economic_transactions', 'economic_entries', 'market_orders', 'market_fills', 'tax_obligations', 'bank_deposits', 'bank_loans', 'corporation_research_projects', 'proposals', 'event_outbox'];
async function fingerprint(connectionString) {
  const client = new Client({ connectionString });
  await client.connect();
  const values = {};
  for (const table of fingerprintTables) {
    const result = await client.query(`SELECT COUNT(*)::TEXT AS count FROM ${table}`);
    values[table] = result.rows[0].count;
  }
  const world = await client.query("SELECT id, game_day, game_minute FROM world_state WHERE id = 'WORLD'");
  await client.end();
  return { values, world: world.rows[0] ?? null };
}

const before = await fingerprint(source);
const { stdout } = await run('node', ['scripts/backup-postgres.mjs'], {
  env: { ...process.env, DATABASE_URL: source, EARTH_BACKUP_DIR: backupDirectory },
  maxBuffer: 1024 * 1024,
});
const backup = JSON.parse(stdout.trim().split('\n').at(-1));
await run('node', ['scripts/restore-postgres.mjs'], {
  env: { ...process.env, RECOVERY_DATABASE_URL: recovery, EARTH_BACKUP_FILE: backup.path, EARTH_ALLOW_RESTORE: 'true' },
  maxBuffer: 1024 * 1024,
});

const after = await fingerprint(recovery);
if (JSON.stringify(before) !== JSON.stringify(after)) throw new Error('Backup/restore fingerprint mismatch');
const checks = ['db:verify:canonical', 'db:verify:manifest', 'db:verify:surface', 'db:verify:invariants', 'db:verify:integrity', 'db:verify:economy-cutover', 'db:verify:finance-cutover'];
for (const check of checks) await run('npm', ['run', check], { env: { ...process.env, DATABASE_URL: recovery }, maxBuffer: 4 * 1024 * 1024 });
console.log(JSON.stringify({ ok: true, certification: 'backup-restore', backup: backup.file, fingerprint: after }));
