import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to back up an implicit database target');
const outputDirectory = process.env.EARTH_BACKUP_DIR || 'backups';
const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const dumpPath = join(outputDirectory, `earth-postgres-${timestamp}.dump`);
await mkdir(outputDirectory, { recursive: true });
await run('pg_dump', ['--format=custom', '--no-owner', '--no-privileges', '--dbname', connectionString, '--file', dumpPath], { maxBuffer: 1024 * 1024 });
const dump = await (await import('node:fs/promises')).readFile(dumpPath);
const metadata = { file: basename(dumpPath), sha256: createHash('sha256').update(dump).digest('hex'), createdAt: new Date().toISOString(), retentionDays: Number(process.env.EARTH_BACKUP_RETENTION_DAYS || 30), encryptedAtRest: process.env.EARTH_BACKUP_ENCRYPTED_AT_REST === 'true' };
await writeFile(`${dumpPath}.json`, `${JSON.stringify(metadata, null, 2)}\n`);
console.log(JSON.stringify({ ok: true, ...metadata, path: dumpPath }));
