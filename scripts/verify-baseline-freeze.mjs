import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const migration = await readFile(new URL('db/migrations/001_baseline.sql', root));
const lock = (await readFile(new URL('db/migrations/001_baseline.sha256', root), 'utf8')).trim().split(/\s+/)[0];
const actual = createHash('sha256').update(migration).digest('hex');
if (actual !== lock) throw new Error(`Frozen migration 001 checksum mismatch: expected ${lock}, got ${actual}`);
console.log(JSON.stringify({ ok: true, migration: '001_baseline.sql', checksum: actual, immutable: true }));
