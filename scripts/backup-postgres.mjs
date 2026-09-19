import { createHash } from 'node:crypto';
import { mkdir, readdir, writeFile } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

// Find the newest pg_dump installed via PGDG packages
// (e.g. /usr/lib/postgresql/18/bin/pg_dump), falling back to PATH default.
async function findPgDump() {
  try {
    const pgDir = '/usr/lib/postgresql';
    const versions = (await readdir(pgDir)).filter((v) => /^\d+$/.test(v)).sort((a, b) => Number(b) - Number(a));
    for (const v of versions) {
      const candidate = join(pgDir, v, 'bin', 'pg_dump');
      try { await import('node:fs/promises').then((fs) => fs.access(candidate)); return candidate; } catch {}
    }
  } catch {}
  return 'pg_dump';
}

const pgDump = await findPgDump();
console.log(`Using: ${pgDump}`);
const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to back up an implicit database target');
const outputDirectory = process.env.EARTH_BACKUP_DIR || 'backups';
const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const dumpPath = join(outputDirectory, `earth-postgres-${timestamp}.dump`);
await mkdir(outputDirectory, { recursive: true });
await run(pgDump, ['--format=custom', '--no-owner', '--no-privileges', '--dbname', connectionString, '--file', dumpPath], { maxBuffer: 1024 * 1024 });
const dump = await (await import('node:fs/promises')).readFile(dumpPath);
const metadata = { file: basename(dumpPath), sha256: createHash('sha256').update(dump).digest('hex'), createdAt: new Date().toISOString(), retentionDays: Number(process.env.EARTH_BACKUP_RETENTION_DAYS || 30), encryptedAtRest: process.env.EARTH_BACKUP_ENCRYPTED_AT_REST === 'true' };
await writeFile(`${dumpPath}.json`, `${JSON.stringify(metadata, null, 2)}\n`);
console.log(JSON.stringify({ ok: true, ...metadata, path: dumpPath }));
