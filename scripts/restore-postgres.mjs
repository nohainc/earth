import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash } from 'node:crypto';

const run = promisify(execFile);
const target = process.env.RECOVERY_DATABASE_URL;
const dumpPath = process.env.EARTH_BACKUP_FILE;
if (!target || !dumpPath) throw new Error('RECOVERY_DATABASE_URL and EARTH_BACKUP_FILE are required');
if (process.env.EARTH_ALLOW_RESTORE !== 'true') throw new Error('Refusing restore; set EARTH_ALLOW_RESTORE=true for a dedicated recovery target');
const dump = await readFile(dumpPath);
const metadata = JSON.parse(await readFile(`${dumpPath}.json`, 'utf8'));
if (createHash('sha256').update(dump).digest('hex') !== metadata.sha256) throw new Error('Backup checksum mismatch; refusing restore');
await run('pg_restore', ['--clean', '--if-exists', '--no-owner', '--no-privileges', '--dbname', target, dumpPath], { maxBuffer: 1024 * 1024 });
console.log(JSON.stringify({ ok: true, restored: dumpPath, sha256: metadata.sha256, target: new URL(target).hostname }));
